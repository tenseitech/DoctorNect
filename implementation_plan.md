# Secret Safety Audit & Remediation Plan

I have completed a full secret safety pass across the codebase. Since this is a Flutter/Firebase app (and not a React/Next.js app with Supabase/Stripe/MongoDB), the findings are specific to the Firebase setup.

## 1. Secrets Found

The only "secrets" found in the source code are Firebase configuration keys, which are explicitly designed by Google to be public-safe and included in client applications. However, to strictly comply with the rule of **no string literal secrets in source code**, they need to be moved.

| Secret Type | Location | Current State |
|---|---|---|
| Firebase API Key (Web) | `lib/firebase_options.dart` (Lines 44, 82) | Hardcoded String Literal |
| Firebase API Key (Android) | `lib/firebase_options.dart` (Line 54) | Hardcoded String Literal |
| Firebase API Key (iOS/macOS) | `lib/firebase_options.dart` (Lines 62, 72) | Hardcoded String Literal |
| Google Services JSON | `android/app/google-services.json` | Hardcoded JSON API Keys |
| Google Service Plist | `ios/Runner/GoogleService-Info.plist` | Hardcoded Plist API Keys |

*Note: No Supabase, Stripe, PostgreSQL, MongoDB, Twilio, OpenAI, or JWT signing secrets exist in this repository.*

## User Review Required

> [!WARNING]
> Moving `google-services.json` and `GoogleService-Info.plist` to environment variables is not supported by standard native Firebase SDKs without writing custom build scripts. The industry standard is to add these files to `.gitignore` so they are not checked into version control, and to inject them during your CI/CD pipeline. 

## Proposed Changes

### `firebase_options.dart`
Move all hardcoded API keys to `String.fromEnvironment` for compile-time injection.
- [MODIFY] [firebase_options.dart](file:///c:/Users/Administrator/Downloads/doctor/lib/firebase_options.dart)

### `.env.example`
Create a template file to document the required environment variables.
- [NEW] [.env.example](file:///c:/Users/Administrator/Downloads/doctor/.env.example)

### `.gitignore`
Ignore the `.env` file and the native Firebase config files to prevent future commits of these secrets.
- [MODIFY] [.gitignore](file:///c:/Users/Administrator/Downloads/doctor/.gitignore)

### `README.md`
Add a **Secret Management** section outlining how to run the app with these environment variables, and include the mandatory warning to rotate previously hardcoded secrets.
- [MODIFY] [README.md](file:///c:/Users/Administrator/Downloads/doctor/README.md)

## Verification Plan
1. Check that the app compiles and runs when passing the correct `--dart-define` flags.
2. Verify that no hardcoded `apiKey` strings remain in `firebase_options.dart`.
3. Ensure `.gitignore` correctly targets the sensitive files.
