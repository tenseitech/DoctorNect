# Pre-publish status — DoctorNect

**Date:** 2026-11-08  
**Branch:** `fix/pre-accept-gate-lab-auth`  
**HEAD:** see `git log -1` after latest audit commits  
**Rating:** **5.5 / 10**

| Area | Score note |
|------|------------|
| Auth / Firebase init | **8/10** — idempotent `FirebaseBootstrap` (`35d9bea`); device OTP re-check **NOT DONE** this session |
| SQL proposed (000014–000018) | **7/10** — admin `create_prescription_atomic` + `current_user` notification trigger patched in proposed files; staging probes updated; **not applied** to staging yet |
| Client Firestore cutover | **4/10** — **108** `LIVE_AND_THROWS` (down from 112 after patient booking availability path); booking/prescription opener/doctor prefetch/auth FCM rows **still POST_LAUNCH** |
| Test signal | **7/10** — Flutter guard ON; release smoke **14** real screens pumped (+3 unit = 17 widget tests in file) |
| Infra / integration | **3/10** — Docker integration **NOT RUN** |

---

## Verification

| Suite | Result |
|-------|--------|
| Flutter (`flutter test --reporter json` + `summarize_flutter_json_reporter.js`) | **777 passed, 0 failed** (after booking smoke + web_splash fix; re-run locally) |
| `FirestoreForbiddenGuard` in tests | **ON** (`flutter_test_config.dart`) |
| `release_firestore_forbidden_smoke_test.dart` | **17** tests (**14** MIGRATED entry screens + 3 unit) |
| `backend/functions` `npm test` | re-run per commit; last known **496 pass, 22 skip** |
| Docker integration | **NOT RUN** |
| `npm run audit:firestore-reachability` | **108 LIVE_AND_THROWS**, 54 DEAD, 5 TEST_ONLY |

---

## New tests since ~760 baseline (16 net; splash + audit batch)

1. `SplashDesign matches SVG at 1242×2208 (dpr 1)`  
2. `SplashDesign no overflow at 1080.0×2400.0`  
3. `SplashDesign no overflow at 720.0×1280.0`  
4. `DoctorNectApp shows design splash on first frame`  
5. `only firebase_bootstrap.dart may call Firebase.initializeApp`  
6. `FirebaseBootstrap.initialize twice concurrently does not throw`  
7. `FirebaseBootstrap.initialize twice sequentially does not throw`  
8. `Mobile (non-web) default path preserves SplashScreen behavior` (updated assertions)  
9. `patient appointment BookingFlowScreen` (release smoke)  
10–16. _(prior audit batch: firebase guard, smoke expansions — see `git log` since `d311947`)_

---

## Remaining POST_LAUNCH (consumer)

Patient prescription opener, doctor home + `firestore_data_prefetch`, unified auth deep steps (`:353`, `:380`), doctor connected labs `:204`, clinical prescription forms, lab report upload sheet, patient/ambulance push FCM token persist — see `FIRESTORE_LAUNCH_FLOWS.md`.

Apply **000014–000018** on staging/RDS per `DEPLOY_ORDER.md` before claiming SQL-complete launch.
