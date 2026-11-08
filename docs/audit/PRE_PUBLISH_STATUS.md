# Pre-publish status — DoctorNect

**Date:** 2026-11-08  
**Branch:** `fix/pre-accept-gate-lab-auth`  
**HEAD:** see `git log -1` after flow-migration commits  
**Rating:** **6.0 / 10**

| Area | Note |
|------|------|
| SQL proposed 000014–000018 | Hardened 000016 reconcile (read-only); staging runbook added; **apply on staging NOT RUN** (no `DATABASE_URL` in workspace `.env`) |
| Client Firestore cutover | **79** `LIVE_AND_THROWS` (was 108); core patient/doctor/lab push + prefetch paths bypass `FirestoreService` gate |
| Tests | **781/0** Flutter; `flutter analyze` **0 issues**; release smoke **16** entry screens + **3** unit |
| Device OTP repro | **NOT DONE** |

---

## Verification

| Suite | Result |
|-------|--------|
| `flutter analyze` | **No issues found** |
| Flutter JSON summary | **781 passed, 0 failed** |
| `release_firestore_forbidden_smoke_test.dart` | **19** tests (**16** MIGRATED screens + 3 unit) |
| `npm run audit:firestore-reachability` | **79 LIVE_AND_THROWS** |
| `backend/functions` `npm test` | **496 pass, 22 skip** (re-run after pull) |
| Staging SQL probes | **NOT RUN** — owner: `docs/audit/STAGING_APPLY_RUNBOOK.md` |

---

## Unified auth `:353`/`:380`

Reachable **only** when `effectiveRole == UserType.ambulance` **and** `AmbulanceEnabled.isOn` (`unified_auth_flow_controller.dart` L294–304). Normal patient/doctor/lab/pharmacy OTP uses `FirebaseAuthService.signInWithMobileOtp` (L307–317). Release default: `AmbulanceEnabled.isOn == false` → Firestore ambulance login path **not reachable**.
