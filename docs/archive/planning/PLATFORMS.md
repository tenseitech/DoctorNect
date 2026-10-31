# Medibond — Web, Android & iOS (same features)

Medibond is one Flutter codebase. **Every screen** (patient + doctor) runs on all three platforms.

## Run locally

```powershell
cd C:\Users\Asus\Desktop\doctor

# Android phone / emulator
flutter run -d android

# iOS (Mac + Xcode only)
flutter run -d ios

# Web (Chrome)
flutter run -d chrome

# Web release build
flutter build web
```

## Layout on each platform

| Screen width | Navigation | Content width |
|--------------|------------|---------------|
| Phone (&lt; 600px) | Bottom tabs (same 5 items) | Full width |
| Tablet / desktop web (≥ 600px) | Left **NavigationRail** (same tabs) | Up to 1100px |

No feature is removed on web — only navigation moves to the side on wide screens.

## Feature parity checklist

| Feature | Android | iOS | Web |
|---------|---------|-----|-----|
| Patient: Home, Search, Book, Appointments | ✅ | ✅ | ✅ |
| Patient: Records, Profile, Lab, Family | ✅ | ✅ | ✅ |
| Doctor: Home, Patients, Appointments, Medical Store, Labs, Profile | ✅ | ✅ | ✅ |
| Doctor: Earnings *(planned)* | — | — | — |
| File upload (reports, registration, photos) | ✅ | ✅ | ✅ (`file_picker`) |
| Maps link | ✅ | ✅ | ✅ (new tab) |
| Call doctor / support | ✅ | ✅ | ✅ (or copies number on desktop web) |
| In-app notifications | ✅ | ✅ | ✅ |
| Charts (`fl_chart`) | ✅ | ✅ | ✅ |

## Build for stores / hosting

```powershell
# Android APK
flutter build apk

# Android App Bundle (Play Store)
flutter build appbundle

# iOS (on Mac)
flutter build ios

# Web (deploy `build/web` folder)
flutter build web --release
```

## Firebase (all 3 platforms)

When you add Firebase, register **three** apps in one Firebase project:

1. Android — package `com.medibond.medibond`
2. iOS — bundle ID from `ios/Runner.xcodeproj`
3. Web — run `flutterfire configure` and select **web**

Then use the same Firestore / Auth code on every platform.

## Before release — test matrix

On **each** platform, walk through:

1. Welcome → Patient login → Search → Doctor profile → **Book** → Appointments list  
2. Cancel / reschedule appointment  
3. Records upload, Profile photo, Help & Support call  
4. Welcome → Doctor login → Today queue → Appointment detail → Prescription save  
5. Notifications bell → open target screen  

Resize browser window (web) to confirm bottom nav ↔ side rail switch at 600px.
