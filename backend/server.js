require('dotenv').config();

const crypto = require('node:crypto');
const express = require('express');
const helmet = require('helmet');
const session = require('express-session');
const rateLimit = require('express-rate-limit');
const { google } = require('googleapis');
const jwt = require('jsonwebtoken');
const { listRecentEmails, getEmailById, revokeGoogleToken } = require('./lib/gmail');
const { analyzeEmail } = require('./lib/ai');

const app = express();
const PORT = Number(process.env.PORT || 3000);

for (const key of ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_CALLBACK_URL', 'SESSION_SECRET', 'APP_JWT_SECRET']) {
  if (!process.env[key]) {
    console.error(`Missing required environment variable: ${key}`);
    process.exit(1);
  }
}
if (process.env.SESSION_SECRET.length < 32 || process.env.APP_JWT_SECRET.length < 32) {
  console.error('SESSION_SECRET and APP_JWT_SECRET should each be at least 32 characters.');
  process.exit(1);
}

// In-memory storage keeps this starter simple. Replace with encrypted persistent
// storage and a shared session store before deploying for real users.
const accounts = new Map(); // Google user id => { email, tokens }
const mobileTickets = new Map(); // one-time ticket => { userId, expiresAt }

app.disable('x-powered-by');
app.set('trust proxy', 1); // Required when using an HTTPS reverse proxy/tunnel.
app.use(helmet({ contentSecurityPolicy: false }));
app.use(express.json({ limit: '32kb' }));
app.use(rateLimit({ windowMs: 60_000, limit: 90, standardHeaders: true, legacyHeaders: false }));
app.use(session({
  name: 'mailmind.sid',
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    secure: process.env.COOKIE_SECURE === 'false' ? false : true,
    sameSite: 'lax',
    maxAge: 10 * 60 * 1000,
  },
}));

function oauthClient() {
  return new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_CALLBACK_URL,
  );
}

app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'MailMind AI API' }));

app.get('/auth/google', (req, res) => {
  const state = crypto.randomBytes(32).toString('hex');
  req.session.oauthState = state;
  const authUrl = oauthClient().generateAuthUrl({
    access_type: 'offline',
    prompt: 'consent',
    scope: [
      'openid',
      'email',
      'profile',
      'https://www.googleapis.com/auth/gmail.readonly',
    ],
    state,
  });
  res.redirect(authUrl);
});

app.get('/auth/google/callback', async (req, res) => {
  try {
    const expectedState = req.session.oauthState;
    if (!expectedState || typeof req.query.state !== 'string' || req.query.state !== expectedState) {
      return res.status(400).send('Google sign-in state validation failed. Close this page and try again.');
    }
    delete req.session.oauthState;
    if (typeof req.query.code !== 'string') return res.status(400).send('Google did not return an authorization code.');

    const auth = oauthClient();
    const { tokens } = await auth.getToken(req.query.code);
    auth.setCredentials(tokens);
    const oauth2 = google.oauth2({ version: 'v2', auth });
    const profile = (await oauth2.userinfo.get()).data;
    if (!profile.id || !profile.email) return res.status(400).send('Could not identify the Google account.');

    accounts.set(profile.id, { email: profile.email, tokens });
    const ticket = crypto.randomBytes(32).toString('base64url');
    mobileTickets.set(ticket, { userId: profile.id, expiresAt: Date.now() + 60_000 });
    return res.redirect(`mailmind://auth?ticket=${encodeURIComponent(ticket)}`);
  } catch (error) {
    console.error('OAuth callback failed:', error.message);
    return res.status(500).send('Google sign-in failed. Check backend logs and OAuth configuration.');
  }
});

app.post('/auth/mobile-exchange', (req, res) => {
  const ticket = req.body?.ticket;
  if (typeof ticket !== 'string' || ticket.length < 30) return res.status(400).json({ error: 'Invalid sign-in ticket.' });
  const record = mobileTickets.get(ticket);
  mobileTickets.delete(ticket); // One-time ticket, even if expired.
  if (!record || record.expiresAt < Date.now()) return res.status(401).json({ error: 'Sign-in ticket expired.' });

  const token = jwt.sign({ sub: record.userId }, process.env.APP_JWT_SECRET, { expiresIn: '6h', issuer: 'mailmind-api', audience: 'mailmind-android' });
  return res.json({ token });
});

function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) return res.status(401).json({ error: 'Sign-in required.' });
  try {
    req.user = jwt.verify(header.slice(7), process.env.APP_JWT_SECRET, { issuer: 'mailmind-api', audience: 'mailmind-android' });
    return next();
  } catch {
    return res.status(401).json({ error: 'Session expired. Sign in again.' });
  }
}

app.get('/api/emails', requireAuth, async (req, res) => {
  try {
    const account = accounts.get(req.user.sub);
    if (!account) return res.status(401).json({ error: 'Gmail connection expired. Connect again.' });
    const emails = await listRecentEmails(account.tokens, 15);
    return res.json({ emails });
  } catch (error) {
    console.error('Gmail list failed:', error.message);
    return res.status(502).json({ error: 'Could not fetch Gmail messages. Check token validity and Gmail API settings.' });
  }
});

app.post('/api/analyze', requireAuth, async (req, res) => {
  try {
    const { emailId, task } = req.body || {};
    if (typeof emailId !== 'string' || typeof task !== 'string') return res.status(400).json({ error: 'emailId and task are required.' });
    const account = accounts.get(req.user.sub);
    if (!account) return res.status(401).json({ error: 'Gmail connection expired. Connect again.' });
    const email = await getEmailById(account.tokens, emailId);
    const result = await analyzeEmail(email, task);
    return res.json({ result, task, notice: 'AI output can be wrong; verify dates, facts and security advice.' });
  } catch (error) {
    console.error('Email analysis failed:', error.message);
    return res.status(error.statusCode || 502).json({ error: error.statusCode ? error.message : 'Email analysis failed. Check AI API key, model access and network.' });
  }
});

app.post('/api/logout', requireAuth, async (req, res) => {
  const account = accounts.get(req.user.sub);
  accounts.delete(req.user.sub);
  if (account) await revokeGoogleToken(account.tokens);
  return res.json({ status: 'disconnected' });
});

app.use((error, _req, res, _next) => {
  console.error('Unhandled request error:', error.message);
  res.status(500).json({ error: 'Unexpected server error.' });
});

app.listen(PORT, () => console.log(`MailMind AI backend listening on port ${PORT}`));
