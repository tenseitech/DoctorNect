# Medibond — Firebase connect (Web + Android + iOS)

Follow these steps **in order** on your PC. Code is already prepared; you only need Firebase Console + `flutterfire configure`.

---

## Step 1 — Tools install (ek baar)

PowerShell:

```powershell
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

Login:

```powershell
firebase login
```

PATH check (agar `flutterfire` not found):

```powershell
$env:Path += ";$env:LOCALAPPDATA\Pub\Cache\bin"
flutterfire --version
```

---

## Step 2 — Firebase project banao

1. Open [Firebase Console](https://console.firebase.google.com)
2. **Add project** → name: `Medibond`
3. Analytics: optional (Off is fine for now)
4. **Create project**

---

## Step 3 — Teen apps register karo (same project)

### A) Android

1. Project overview → **Add app** → **Android**
2. Package name (copy exactly):

   ```
   com.medibond.medibond
   ```

3. Register → download **`google-services.json`**
4. Save to:

   ```
   android/app/google-services.json
   ```

### B) iOS

1. **Add app** → **iOS**
2. Bundle ID:

   ```
   com.medibond.medibond
   ```

3. Register → download **`GoogleService-Info.plist`**
4. Save to:

   ```
   ios/Runner/GoogleService-Info.plist
   ```

### C) Web

1. **Add app** → **Web** (</> icon)
2. App nickname: `Medibond Web`
3. Register → copy config (FlutterFire will use this in Step 5)

---

## Step 4 — Console mein services ON

### Authentication

- **Build → Authentication → Get started**
- **Sign-in method → Email/Password → Enable**

### Firestore

- **Build → Firestore Database → Create database**
- **Start in test mode** (development only)
- Region: **asia-south1 (Mumbai)**

### Storage (optional — files / reports)

- **Build → Storage → Get started** → test mode → same region

---

## Step 5 — FlutterFire configure (sabse important)

Project folder:

```powershell
cd C:\Users\Asus\Desktop\doctor
flutter pub get
flutterfire configure
```

Prompts:

| Question | Answer |
|----------|--------|
| Firebase project | **Medibond** (jo banaya) |
| Platforms | **android, ios, web** (space se select) |
| Android package | `com.medibond.medibond` |
| iOS bundle ID | `com.tensei.medibond` |

Yeh file **auto banegi** (commit karna):

```
lib/firebase_options.dart
```

Web ke liye `web/index.html` mein scripts bhi add ho sakti hain — allow karna.

---

## Step 6 — Test run

```powershell
flutter run -d chrome
flutter run -d android
```

Console mein dikhe: `Firebase initialized`

### Firestore test (optional)

Firebase Console → Firestore → **Start collection** → `test` → document `ping` → field `ok: true`

App se baad mein read/write code add karenge.

---

## Step 7 — Build commands

```powershell
flutter build web --release
flutter build apk
# iOS (Mac only):
flutter build ios
```

---

## IDs summary (sab same rakho)

| Platform | ID |
|----------|-----|
| Android package | `com.medibond.medibond` |
| iOS bundle | `com.tensei.medibond` |
| Web | FlutterFire web app id (auto) |

---

## Common errors

| Error | Fix |
|-------|-----|
| `firebase_options.dart` not found | Run `flutterfire configure` (Step 5) |
| `google-services.json` missing | Step 3A — file in `android/app/` |
| Gradle google-services error | `flutter clean` → `flutter pub get` |
| iOS build fail | `GoogleService-Info.plist` in `ios/Runner/` |
| Web blank after Firebase | Hard refresh; check `web/index.html` scripts from FlutterFire |

---

## Already in this repo

- `pubspec.yaml`: `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`
- `lib/main.dart`: `initializeFirebase()` on startup
- `android`: Google Services plugin
- `lib/core/firebase/firebase_bootstrap.dart`

**You must complete Steps 2–5** (Console + `flutterfire configure`) before the app will compile.
