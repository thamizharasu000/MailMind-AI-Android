# MailMind AI — Android starter project

**MailMind AI** is a Flutter Android app + Node.js backend starter for smarter email handling. The included UI has an inbox, daily overview, tasks, AI assistant actions, reply drafting, and phishing-awareness checks. Custom app logo and feature assets are included.

> **What is included:** Flutter source, visual assets, Gmail OAuth backend, Gmail message fetcher, Gemini API integration, setup docs, an APK build script, and a GitHub Actions workflow that can build an APK.
>
> **What is not included:** A prebuilt `.apk`. This workspace does not have the Flutter SDK/Android build toolchain installed, so the APK could not be compiled and tested here. Use the provided build script or the GitHub Actions workflow to build it.

## Project contents

```text
MailMind_AI_Complete/
├── mobile/                     # Flutter source app
│   ├── lib/main.dart
│   ├── lib/models/email_item.dart
│   ├── lib/services/api_service.dart
│   ├── lib/screens/home_screen.dart
│   ├── assets/brand/            # Logo, app icon and splash art
│   └── assets/features/         # Summary, tasks, reply, security, avatar
├── backend/                     # Node.js + Express API
│   ├── server.js
│   ├── lib/gmail.js
│   ├── lib/ai.js
│   └── .env.example
├── assets/                      # Copy of all source assets
├── tools/build_apk.sh           # Build APK on a computer with Flutter
├── .github/workflows/           # Optional cloud APK build workflow
└── docs/                        # Project plan and security notes
```

## Features in this starter

- **Inbox UI:** real Gmail list when connected; clearly labelled sample messages before connecting.
- **AI summary:** short key points, sender request, and explicit dates.
- **Task extraction:** action items and deadlines; missing deadlines must remain marked as not specified.
- **AI reply draft:** creates text for the user to review; this starter does **not** send messages.
- **Phishing-awareness review:** checks email text for suspicious indicators and gives safer-next-step advice. It does not visit links, scan attachments, or guarantee a message is safe.
- **Google OAuth:** browser-based authorization and a short-lived one-use ticket back to the app.
- **Token storage:** app session token stored using `flutter_secure_storage`.
- **Brand assets:** original logo PNG/SVG, Android icon source, splash illustration, and feature tiles.

## 1. Install the tools

Install Flutter and its Android requirements using the official guide:

- https://docs.flutter.dev/platform-integration/android/setup
- https://docs.flutter.dev/get-started/install

Install Node.js 20 or later. You need Android SDK build tools to generate an APK. The build script creates the Android platform folder from the installed Flutter SDK, so the ZIP keeps the Flutter source clean and portable.

## 2. Run the app in demo mode

The app can show its sample inbox without connecting Gmail.

```bash
cd MailMind_AI_Complete/mobile
flutter pub get
```

The ZIP intentionally keeps the Android host files generated at build time so they match the Flutter SDK installed on your computer. Use the root `tools/build_apk.sh` script to create the temporary Android host, copy in the included Dart code/assets, and build the APK without overwriting this source tree.

## 3. Configure the backend

```bash
cd MailMind_AI_Complete/backend
cp .env.example .env
npm install
```

Open `.env` and fill in:

- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_CALLBACK_URL`
- `SESSION_SECRET` (long, random secret)
- `APP_JWT_SECRET` (a different long, random secret)
- `GEMINI_API_KEY`
- `GEMINI_MODEL` (default `gemini-3.8-flash`; change it if your API account uses a different supported model)

Start the API:

```bash
npm run dev
```

`http://localhost:3000/health` should return a JSON status. Do not deploy the backend publicly until you have configured HTTPS, secure persistent sessions, encrypted token storage, and appropriate access controls.

## 4. Configure Google OAuth / Gmail

1. Open https://console.cloud.google.com/ and create a project.
2. Enable **Gmail API**.
3. Configure the OAuth consent screen and add your Google account as a test user.
4. Create an OAuth client of type **Web application**.
5. Configure the authorized redirect URI to exactly match `GOOGLE_CALLBACK_URL`, for example `https://YOUR_PUBLIC_HOST/auth/google/callback`.
6. Keep your Google client secret in the backend `.env` only.

### Local Android testing needs a reachable HTTPS URL

Google sends the browser back to the backend. For a phone/emulator, use an HTTPS development tunnel (such as ngrok or Cloudflare Tunnel) to expose your local Node API. Use the same HTTPS host for all three:

- `GOOGLE_CALLBACK_URL=https://YOUR_PUBLIC_HOST/auth/google/callback`
- The OAuth redirect URI in Google Cloud Console
- The app's `MAILMIND_API_BASE` build value: `https://YOUR_PUBLIC_HOST`

The OAuth start request and callback must share a host so the OAuth state session cookie works. If the public tunnel URL changes, update the environment value and the Google Cloud Console redirect URI.

Build with the public URL:

```bash
MAILMIND_API_BASE=https://YOUR_PUBLIC_HOST ./tools/build_apk.sh
```

For the Android emulator only, `http://10.0.2.2:3000` is the default API base, but it is not enough for a browser OAuth callback by itself. Use the HTTPS tunnel configuration for the whole OAuth flow.

## 5. Configure Gemini AI

Create an API key through https://aistudio.google.com/apikey and put it in the backend `.env`. Never place `GEMINI_API_KEY` in the Flutter app or commit the `.env` file.

Email text may contain personal or confidential information. The analysis route sends the selected email content to the configured AI provider. Tell users about this and only analyze messages with appropriate consent.

## 6. Build an APK

On a computer with Flutter + Android SDK + an internet connection:

```bash
cd MailMind_AI_Complete
./tools/build_apk.sh
```

When successful, the APK will be written to:

```text
dist/MailMind_AI.apk
```

If you have a backend reachable at a public HTTPS URL, set it before building:

```bash
MAILMIND_API_BASE=https://YOUR_PUBLIC_HOST ./tools/build_apk.sh
```

### Cloud build (no Flutter SDK on your own machine)

1. Upload this folder to a GitHub repository (do not upload `backend/.env`).
2. Open the repository's **Actions** tab.
3. Run **Build MailMind AI APK** using **Run workflow**, or push to `main` / `master`.
4. Download the `MailMind-AI-Android-APK` artifact from the completed workflow run.

Optional: configure a GitHub Actions repository variable named `MAILMIND_API_BASE` with your public HTTPS backend URL. Without it, the APK's Gmail buttons will point at the emulator default and won't connect from a physical phone.

## 7. Install the APK on Android

Copy `MailMind_AI.apk` to the phone, tap it, and permit installation from that file manager if Android asks. Only install APKs you built or trust. If Android reports a package/signature mismatch, uninstall an older build first.

## Current starter limitations

- Backend OAuth accounts, mobile tickets, and refresh tokens are in memory. Restarting Node loses them, so users must sign in again. Use a database and encrypted token storage before a real release.
- Google OAuth restricted scopes may require verification and a security assessment for public distribution. Review Google's current requirements before publishing: https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification
- Session store is Express's development MemoryStore; replace it for deployment.
- The app's tasks tab is a local sample checklist. Extracted AI tasks are shown as suggestions but are not synced to Google Tasks or Calendar.
- AI output can be incorrect. Phishing scoring is heuristic and cannot guarantee safety.
- The build script currently enables Android cleartext for local development. For production, remove `android:usesCleartextTraffic="true"` and use HTTPS only.

See `docs/PROJECT_PLAN.md` and `docs/SECURITY_NOTES.md` for next steps.
