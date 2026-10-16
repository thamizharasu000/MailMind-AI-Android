# MailMind AI — Project plan

## Goal
Build an Android-first assistant that helps users understand long emails, track requested actions, draft replies, and notice possible phishing patterns without sending mail automatically.

## Milestones

### M1 — Mobile shell and brand
- Flutter navigation: Inbox, Tasks, AI Assist, Security.
- Logo/app icon/splash assets.
- Sample emails and clearly labelled demo output.

### M2 — Google sign-in
- Google Cloud project, Gmail API, OAuth consent/test users.
- Browser OAuth with state validation and short-lived mobile ticket.
- Store only app session token in Android secure storage.

### M3 — Gmail inbox
- Fetch recent inbox messages with least-privilege read scope.
- Handle MIME text, plain text, fallback snippets, and API errors.
- Do not auto-download attachments.

### M4 — AI functions
- Summary: 3–5 key points.
- Tasks: actions with only explicitly supported dates.
- Reply: draft only, user review required.
- Phishing: indicators and safe next steps; no claim of guaranteed detection.

### M5 — Release hardening
- Replace in-memory token/account maps with encrypted persistent storage.
- Use persistent session store and HTTPS-only cookies.
- Add token revocation, rate limits, request validation, redacted logs, privacy notice, data deletion, and monitoring.
- Test against malformed emails, prompt-injection text, HTML-only messages and expired tokens.
- Complete OAuth verification and policy review before public release.

## Acceptance criteria
- No Google client secret or AI key in the mobile app.
- User can inspect and edit a generated reply before any external action.
- A date is shown only when supported by the source email; otherwise “not specified”.
- Phishing view describes evidence and limitations.
- Demo email data is distinguishable from live Gmail messages.
- APK builds reproducibly in CI and is stored as an artifact.
