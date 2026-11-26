# Android release APK — local toolchain and CI

**Status:** Operator note (docs only).  
**Purpose:** Match **GitHub Actions** release builds; avoid accidental Gradle upgrades on developer machines.

---

## Pinned versions (repo / CI)

| Component | Pin | Where |
|-----------|-----|--------|
| **Flutter** | **3.47.5** (stable) | `.github/workflows/build-apk.yml`, `.github/workflows/flutter-ci.yml` |
| **Gradle wrapper** | **8.14** | `frontend/android/gradle/wrapper/gradle-wrapper.properties` |
| **AGP** | 8.11.1 | `frontend/android/settings.gradle.kts` |
| **Kotlin** | 2.2.20 | same |
| **Dart SDK constraint** | `>=3.2.0 <4.0.0` | `frontend/pubspec.yaml` (no Flutter SDK pin in pubspec) |
| **FVM** | Not used | No `.fvmrc` in repo |

**Do not build release APK with Flutter 3.50.x** (or newer stable) against this repo’s current Android Gradle stack: Flutter enforces a **minimum Gradle version above 8.14**, so `flutter build apk --release` fails before compile. This is a **toolchain mismatch**, not an app regression.

---

## Local release build (recommended)

1. Install Flutter **3.47.5** side-by-side (do **not** downgrade the global SDK if other projects need 3.50.x). Example layout: `C:\flt3475\flutter` from [Flutter archive](https://docs.flutter.dev/release/archive) (`flutter_windows_3.47.5-stable.zip`).
2. Put that SDK **first** on `PATH` for the build shell only.
3. From repo root, prepare secrets the same way CI does for Firebase options, and use **local** signing files (gitignored):

```powershell
$env:Path = "C:\flt3475\flutter\bin;" + $env:Path
cd frontend
if (-not (Test-Path lib\firebase_options.secrets.dart)) {
  Copy-Item lib\firebase_options.secrets.example.dart lib\firebase_options.secrets.dart
}
# Requires frontend/android/key.properties and upload-keystore.jks (repo root, paths in key.properties)
flutter pub get
flutter build apk --release
```

**Output:** `frontend/build/app/outputs/flutter-apk/app-release.apk`

**Java:** CI uses **Temurin 17**; local JDK 21 often works but use 17 if Gradle/Kotlin errors appear.

---

## CI gap — release signing

`.github/workflows/build-apk.yml` runs `flutter build apk --release` but does **not** provision:

- `frontend/android/key.properties`
- `upload-keystore.jks` (or equivalent)

Since `1534677`, `frontend/android/app/build.gradle.kts` **fails closed** on release tasks without a valid release keystore (no debug fallback). **Expect CI release APK jobs to fail** until signing secrets are added (e.g. GitHub Actions secrets + workflow step to materialize `key.properties` and keystore). Local builds with gitignored signing files can still succeed.

---

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Gradle version / minimum 9.x error | Flutter **3.50+** on PATH — switch to **3.47.5** |
| `key.properties` / keystore FATAL | Missing or wrong `storeFile` path (`../../upload-keystore.jks` from `android/`) |
| Flutter/AGP/Gradle “soon be dropped” warnings on 3.47.5 | Informational; build can still succeed |

---

## References

- Workflow: `.github/workflows/build-apk.yml`
- Part D ops: `docs/ops/MSG91_SMS_BUDGET_DESIGN.md` (unrelated; same ops folder)