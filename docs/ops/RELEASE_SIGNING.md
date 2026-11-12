# Mobile Release Signing Specification (Fail-Closed)

## Fail-Closed Signing Invariant
In `frontend/android/app/build.gradle.kts`, the `release` build type strictly binds to `signingConfigs.getByName("release")` and **never falls back to debug signing**.

### Behavior
1. **Release Builds (`bundleRelease`, `assembleRelease`):**
   - Requires `frontend/android/key.properties` (or root `key.properties`).
   - Requires the referenced keystore file (`upload-keystore.jks`) to exist on disk.
   - If either file is missing, Gradle throws a fatal `GradleException` during task evaluation:
     `FATAL: Release keystore file specified in key.properties was not found. Release builds must never fall back to debug signing.`
2. **Debug Builds (`assembleDebug`, `flutter run`, `flutter test`):**
   - Retain default debug signing credentials.
   - Continue to build and execute cleanly on local developer machines without `key.properties`.

### Security Note
- Keystore passwords, aliases, and paths are read via `FileInputStream` directly into `Properties`.
- Passwords and sensitive parameters are never printed to console or logs.
