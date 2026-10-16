#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter SDK not found. Install Flutter and Android SDK first: https://docs.flutter.dev/platform-integration/android/setup" >&2
  exit 1
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
PROJECT="$TMP/mailmind_android_build"

flutter create --platforms=android --org com.mailmind --project-name mailmind_ai "$PROJECT" --no-pub
cp "$ROOT/mobile/pubspec.yaml" "$PROJECT/pubspec.yaml"
rm -rf "$PROJECT/lib" "$PROJECT/assets"
cp -R "$ROOT/mobile/lib" "$PROJECT/lib"
cp -R "$ROOT/mobile/assets" "$PROJECT/assets"
cp "$ROOT/mobile/analysis_options.yaml" "$PROJECT/analysis_options.yaml"

cat > "$PROJECT/android/app/src/main/AndroidManifest.xml" <<'MANIFEST'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:label="MailMind AI"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data android:name="io.flutter.embedding.android.NormalTheme" android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="mailmind" android:host="auth" />
            </intent-filter>
        </activity>
        <meta-data android:name="flutterEmbedding" android:value="2" />
    </application>
</manifest>
MANIFEST

# Set a custom launcher icon when dependencies can be fetched; the build still
# succeeds if the generator package is temporarily unavailable.
(
  cd "$PROJECT"
  flutter pub get
  dart run flutter_launcher_icons || echo "NOTE: launcher icon generator failed; using Flutter default icon."
  mkdir -p "$ROOT/dist"
  API_BASE="${MAILMIND_API_BASE:-http://10.0.2.2:3000}"
  flutter build apk --release --dart-define="MAILMIND_API_BASE=$API_BASE"
  cp build/app/outputs/flutter-apk/app-release.apk "$ROOT/dist/MailMind_AI.apk"
)
echo "APK created: $ROOT/dist/MailMind_AI.apk"
