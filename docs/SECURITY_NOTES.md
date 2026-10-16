# Security and privacy notes

## Sensitive data
- Gmail message bodies can contain personal, financial, education, and account information.
- This starter sends the selected message's text to the configured Gemini API for analysis. Obtain appropriate user consent and clearly disclose processing/retention before wider use.
- Do not log email body text, OAuth tokens, one-time tickets, or AI keys.

## Required before public release
- Replace in-memory `accounts` and `mobileTickets` maps with durable storage that supports encryption, expiry, single-use tickets, and multi-instance deployment.
- Replace Express MemoryStore with a production session store.
- Use secure HTTPS deployment, secure cookies, rate limiting, abuse controls, CSRF/state defenses, strict URL/host validation and an explicit CORS policy if a web client is added.
- Add account deletion and proper Google grant revocation handling.
- Consider access token refresh and refresh-token rotation, expiry, revocation and failed authorization flows.
- Scope review: `gmail.readonly` is a restricted Gmail scope. Ask for no more access than the features require and review Google's verification/security-assessment requirements.
- Do not auto-send replies in the first release. Keep the user in control.
- Treat email text, URLs, filenames, headers and model output as untrusted. AI prompt instructions alone are not a full prompt-injection defense.
- Phishing analysis does not visit links or scan attachments. Use a reputable safe-browsing/reputation service only after privacy and product review; do not imply coverage that is not implemented.

## Local development
The provided `tools/build_apk.sh` enables cleartext traffic for development compatibility. For release builds, use HTTPS for every network request and remove the cleartext exception.
