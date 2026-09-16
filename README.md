# Medibond

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Secret Management

To comply with secret safety checks, no API keys or configuration secrets are stored as string literals in the source code.

**Firebase Configuration:**
Firebase Web, Android, and iOS API keys are passed at compile time using `--dart-define`.
Example:
```bash
flutter run --dart-define=FIREBASE_API_KEY_WEB=your_key --dart-define=FIREBASE_API_KEY_ANDROID=your_key --dart-define=FIREBASE_API_KEY_IOS=your_key
```

**Native Config Files:**
The `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) files are added to `.gitignore`. You must inject these files via your CI/CD pipeline or place them locally.

> **WARNING:** Any secrets (such as Firebase API keys) that were previously hardcoded in this repository's git history are exposed. You must rotate any previously hardcoded secrets immediately to ensure your Firebase project's security.

## Google OAuth and Location Setup

Google Sign-In on web requires replacing the placeholder in `web/index.html`:

```text
REPLACE_WITH_WEB_CLIENT_ID.apps.googleusercontent.com
```

Use the Web Client ID from Firebase Console > Authentication > Sign-in method > Google > Web SDK configuration. Also confirm Google is enabled as a Firebase sign-in provider and that local development origins such as `localhost` are authorized for the web OAuth client.

For precise "Use current location" reverse geocoding, enable the Google Maps Geocoding API in Google Cloud Console, create and restrict an API key, and enable billing. Google requires billing even when usage stays inside the monthly credit. Run the app with:

```bash
flutter run -d chrome --dart-define=GOOGLE_MAPS_API_KEY=your_key_here
```

or:

```bash
flutter run -d web-server --web-port=8091 --dart-define=GOOGLE_MAPS_API_KEY=your_key_here
```

If the key is omitted, invalid, or over quota, the app falls back to the free `geocoding` package.

## Android release builds (Play Store)

Release AAB builds require a unique **versionCode** (the number after `+` in `pubspec.yaml`).
Use the release script so you do not have to bump it manually before every upload.

**Setup (once):**

1. Copy `.env.example` to `.env` if you have not already.
2. Set `FIREBASE_API_KEY_ANDROID` in `.env` (required for release builds).

**Windows:**

```powershell
.\scripts\release_build.ps1
```

**macOS / Linux:**

```bash
./scripts/release_build.sh
```

The script will:

1. Read the current `version:` line in `pubspec.yaml` (e.g. `1.0.1+2`)
2. Increment only the versionCode (`2` → `3`), leaving the versionName (`1.0.1`) unchanged
3. Run `flutter build appbundle --release` with the project's `--dart-define` flags
4. Print the final versionCode and AAB path for Play Console upload

**Optional flags:**

| Flag | PowerShell | Bash |
|------|------------|------|
| Preview bump without building | `-DryRun` | `--dry-run` |
| Build without incrementing versionCode | `-SkipIncrement` | `--skip-increment` |

To change the user-facing version name (e.g. `1.0.1` → `1.0.2`), edit `pubspec.yaml` manually before running the script.

Output AAB: `build/app/outputs/bundle/release/app-release.aab`
