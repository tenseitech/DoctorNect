# Firebase App Check setup (DoctorNect Android)

Firebase project: `medibond-45fad` (Google Cloud project number `658118593597`).
Android app id: `com.tenseitech.doctornect`.

The OTP and other callables run with `enforceAppCheck` (`ENFORCE_OTP_APP_CHECK=true`,
`ENFORCE_ABUSE_APP_CHECK=true`). A request without a valid App Check token is rejected with
`401 UNAUTHENTICATED`, which the app shows as a security verification error with a reason code:

| Code in the message | Meaning |
|---|---|
| `app_check_token_missing` | This install could not get a token (sideloaded build, Play Integrity not available, or an unregistered debug token). |
| `app_check_rate_limited` | Token requests were throttled after repeated failures. Wait a minute and restart the app. |
| `app_check_token_rejected` | A token was sent but the server refused it. |

## Which provider each build uses

| Build | Provider |
|---|---|
| `flutter run` (debug) | Debug provider |
| Release, built with `--dart-define=APP_ENV=staging --dart-define=APP_CHECK_DEBUG_PROVIDER=true` | Debug provider (staging test APK only) |
| Any other release build, including `scripts/release_build.ps1` / `.sh` | Play Integrity |
| Any build with `APP_ENV=production` | Play Integrity. Adding `APP_CHECK_DEBUG_PROVIDER=true` makes the app fail at startup on purpose. |

The release scripts reject `APP_CHECK_DEBUG_PROVIDER` and any `*DEBUG_TOKEN*` dart-define.
Rules live in `frontend/lib/core/security/app_check_provider_policy.dart` and are covered by
`frontend/test/app_check_provider_policy_test.dart`.

## 1. Test a sideloaded build with the debug provider (staging only)

1. Build the staging test APK (signed with your release key, debug App Check provider):
   ```powershell
   cd frontend
   flutter build apk --release --dart-define=APP_ENV=staging --dart-define=APP_CHECK_DEBUG_PROVIDER=true
   Copy-Item build\app\outputs\flutter-apk\app-release.apk build\app\outputs\flutter-apk\app-staging-appcheck-debug.apk
   ```
2. Install it on the phone (replaces the installed app, keeps the same signing key):
   ```powershell
   adb install -r build\app\outputs\flutter-apk\app-staging-appcheck-debug.apk
   ```
3. Start logcat filtered on the debug provider, then open the app:
   ```powershell
   adb logcat -s DebugAppCheckProvider
   ```
   Look for the line `Enter this debug secret into the allow list in the Firebase Console for your project: <UUID>`.
   The UUID is a credential. Do not paste it into chat, tickets or git.
4. Firebase console → **App Check** → **Apps** → `com.tenseitech.doctornect` → overflow menu (⋮) →
   **Manage debug tokens** → **Add debug token** → name it (for example `EB2101 staging`) → paste the UUID → **Save**.
5. Force-stop the app and open it again. OTP requests now pass App Check.
6. Delete the debug token in the same screen when you stop testing on that device. Anyone who has a
   registered debug token can pass App Check.

A debug token is tied to the app's local storage. Clearing app data or reinstalling creates a new UUID,
which you must register again.

## 2. SHA-256 fingerprints

Run these yourself. `keytool` asks for the keystore password interactively, so the password never
appears in a command line, a file or chat.

Upload / release key (the keystore named in `frontend/android/key.properties`):
```powershell
& "$env:JAVA_HOME\bin\keytool.exe" -list -v -keystore <path-to-your-upload-keystore.jks> -alias <your-key-alias>
```
Copy the `SHA256:` line (and `SHA1:` if you use Google Sign-In / Phone Auth).

Add it in Firebase console → **Project settings** → **General** → **Your apps** →
Android app `com.tenseitech.doctornect` → **Add fingerprint**.

After the first upload to Google Play (Play App Signing):
Play Console → your app → **Test and release** → **App integrity** → **App signing** →
copy **App signing key certificate** SHA-256 (and SHA-1) → add both in Firebase as above.
Play-installed builds are signed with that key, not your upload key.

To check which certificate a built APK carries:
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\<version>\apksigner.bat" verify --print-certs frontend\build\app\outputs\flutter-apk\app-release.apk
```
(This machine uses `C:\Android\build-tools\36.0.0\apksigner.bat`.)

## 3. Play Integrity for production builds

1. Google Cloud console → project `medibond-45fad` (number `658118593597`) → **APIs & Services** →
   **Enable APIs** → enable **Google Play Integrity API**.
2. Play Console → your app → **Test and release** → **App integrity** → **Play Integrity API** →
   **Link a Cloud project** → choose `658118593597`.
3. Firebase console → **App Check** → **Apps** → `com.tenseitech.doctornect` → **Play Integrity** →
   register. Make sure the SHA-256 fingerprints from step 2 are present on the Android app.
4. Keep App Check **enforced** for Cloud Functions. Do not set `ENFORCE_OTP_APP_CHECK=false` in production
   (production boot refuses it).

## 4. Real Play Integrity check via Internal testing

Play Integrity only vouches for apps installed by Google Play. A locally built APK that is sideloaded
(`adb install`, file manager) gets no valid verdict, so it can never pass App Check with the Play
Integrity provider. That is the error seen on the EB2101 test phone.

1. Build the production bundle: `scripts/release_build.ps1` (or `flutter build appbundle --release`).
2. Play Console → **Test and release** → **Testing** → **Internal testing** → **Create new release** →
   upload the `.aab` → **Save** → **Review release** → **Start rollout to Internal testing**.
3. **Testers** tab → add your Google account to the tester list → copy the opt-in link.
4. On the phone: uninstall the sideloaded app first (different signing key), open the opt-in link with
   the same Google account, accept, and install from the Play Store link.
5. Request an OTP. If it still fails, check `adb logcat -s PlayCore Finsky`. On the EB2101 the sideloaded
   test also logged `IntegrityKeyAttestationException ... Keystore code -49` from Google Play itself.
   If that appears for the Play-installed build too, the phone's hardware keystore attestation is broken
   (update the phone / Google Play services, or test on another device).
