const { google } = require('googleapis');

function gmailClient(tokens) {
  const auth = new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_CALLBACK_URL,
  );
  auth.setCredentials(tokens);
  return google.gmail({ version: 'v1', auth });
}

function decodeBase64Url(value = '') {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  return Buffer.from(normalized, 'base64').toString('utf8');
}

function stripHtml(value) {
  return value
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractText(payload) {
  if (!payload) return '';
  // Prefer text/plain wherever present; never auto-download attachments.
  if (payload.mimeType === 'text/plain' && payload.body?.data) {
    return decodeBase64Url(payload.body.data);
  }
  for (const part of payload.parts || []) {
    const text = extractText(part);
    if (text) return text;
  }
  if (payload.mimeType === 'text/html' && payload.body?.data) {
    return stripHtml(decodeBase64Url(payload.body.data));
  }
  return '';
}

function headerValue(headers = [], wantedName) {
  const found = headers.find((header) =>
    String(header.name || '').toLowerCase() === wantedName.toLowerCase(),
  );
  return found?.value || '';
}

function cleanMessage(message) {
  const headers = message.payload?.headers || [];
  const body = extractText(message.payload).slice(0, 12000);
  return {
    id: message.id,
    threadId: message.threadId,
    from: headerValue(headers, 'from'),
    to: headerValue(headers, 'to'),
    subject: headerValue(headers, 'subject') || '(No subject)',
    date: headerValue(headers, 'date'),
    snippet: message.snippet || body.slice(0, 180),
    body: body || message.snippet || '',
    // Labels are metadata; do not treat them as a security verdict.
    labels: message.labelIds || [],
  };
}

async function listRecentEmails(tokens, maxResults = 15) {
  const gmail = gmailClient(tokens);
  const response = await gmail.users.messages.list({
    userId: 'me',
    maxResults: Math.min(Math.max(maxResults, 1), 25),
    q: 'in:inbox -category:spam -category:trash',
  });
  const messages = response.data.messages || [];
  const full = await Promise.all(messages.map(async ({ id }) => {
    const result = await gmail.users.messages.get({
      userId: 'me',
      id,
      format: 'full',
    });
    return cleanMessage(result.data);
  }));
  return full;
}

async function getEmailById(tokens, id) {
  if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{1,200}$/.test(id)) {
    throw new Error('Invalid email id');
  }
  const gmail = gmailClient(tokens);
  const result = await gmail.users.messages.get({
    userId: 'me',
    id,
    format: 'full',
  });
  return cleanMessage(result.data);
}

async function revokeGoogleToken(tokens) {
  const token = tokens?.refresh_token || tokens?.access_token;
  if (!token) return;
  try {
    const client = new google.auth.OAuth2(
      process.env.GOOGLE_CLIENT_ID,
      process.env.GOOGLE_CLIENT_SECRET,
      process.env.GOOGLE_CALLBACK_URL,
    );
    await client.revokeToken(token);
  } catch (error) {
    // Revocation failures shouldn't prevent local logout; report only safe details.
    console.warn('Google token revoke did not complete:', error.message);
  }
}

module.exports = { listRecentEmails, getEmailById, revokeGoogleToken };
