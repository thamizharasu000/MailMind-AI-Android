# Flutter app source

The Dart source and assets are here. The root `tools/build_apk.sh` script generates the matching Android host project with your installed Flutter SDK, then builds `dist/MailMind_AI.apk`.

The app opens Google sign-in in the system browser and receives a `mailmind://auth` callback. The Android manifest deep link is configured by the build script.
