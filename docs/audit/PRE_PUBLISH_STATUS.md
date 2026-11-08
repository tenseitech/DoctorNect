# Pre-publish status — DoctorNect

**Date:** 2026-11-08  
**Branch:** `fix/pre-accept-gate-lab-auth`  
**HEAD:** `35d9bea` (+ pending doc/SQL commit)  
**Rating:** **7.0 / 10** (Firebase login duplicate-app fixed; **112** LIVE_AND_THROWS; guard ON in tests **772/0**)

---

## Verification

| Suite | Result |
|-------|--------|
| Flutter (`flutter test --reporter json` + `summarize_flutter_json_reporter.js`) | **772 passed, 0 failed, 0 skipped** |
| `FirestoreForbiddenGuard` in tests | **ON by default** (`flutter_test_config.dart`); opt-in `allowFirestoreInThisTestFile()` only in files that need fakes |
| `release_firestore_forbidden_smoke_test.dart` | **16 passed** (13 MIGRATED entry screens + 3 unit) |
| `backend/functions` `npm test` | **496 pass, 22 skip** |
| Docker integration (4 files) | **NOT RUN** — Docker Desktop down; Postgres **:54322 unreachable** |
| `npm run audit:firestore-reachability` | **112 LIVE_AND_THROWS**, 54 DEAD, 5 TEST_ONLY (shared-core: **27** LIVE) |

---

## Highlights

- Idempotent `FirebaseBootstrap.initialize()` (`duplicate-app` + `Firebase.apps` guard) — unblocks OTP Continue on Android auto-init.
- Flow inventory: `docs/audit/FIRESTORE_LAUNCH_FLOWS.md`; reachability: `FIRESTORE_REACHABLE_RELEASE.md`.
- Lab report RPC skew user message in `SupabaseLabRepository.labReportRpcSkewMessage`.
- **000016** trigger: `SECURITY INVOKER` + `session_user` + `app.in_app_notifications_trusted_patch` for definer-under-JWT server patches.

---

## Remaining POST_LAUNCH

Patient booking, prescription opener, doctor home prefetch, unified auth deep steps, doctor connected labs orders sub, clinical prescription forms — see launch flow doc. Apply **000014–000018** on staging/RDS per `DEPLOY_ORDER.md`.
