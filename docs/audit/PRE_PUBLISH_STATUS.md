# Pre-publish status — DoctorNect

**Date:** 2026-11-07  
**Branch:** `fix/pre-accept-gate-lab-auth`  
**Rating:** **6.8 / 10** (up from 6.6; **136** LIVE_AND_THROWS rows remain vs 173; not ≥7 until booking/clinical/prefetch paths migrate or wrap)

---

## Verification

| Suite | Result |
|-------|--------|
| Flutter `test_results_clean.json` | **760 passed, 0 failed** (guard ON globally; per-file `allowFirestoreInThisTestFile` only) |
| `backend/functions` `npm test` | **496 pass, 22 skip** (unchanged) |
| Docker integration (`s3_supabase_docker_integration`, `delete_my_account_docker_integration`) | **skipped** — Docker daemon up but **Postgres :54322 unreachable** |
| `npm run audit:firestore-reachability` | **136 LIVE_AND_THROWS**, 54 DEAD, 5 TEST_ONLY |

---

## Highlights this pass

- Reverted global test Firestore bypass; `test/helpers/firestore_test_access.dart` opt-in only.
- Launch paths: doctor directory, verification gate, pharmacy connections, auth `UserRepository`, notification sync → Postgres repos without `FirestoreService` gateway.
- `release_firestore_forbidden_smoke_test.dart` pumps 5 launch entry screens under `debugForceReleaseMode`.
- Lab RPC schema skew user message; `000016` trigger uses `current_user` for SECURITY DEFINER bypass.

---

## Remaining

1. **LIVE_AND_THROWS** on booking, clinical prescription forms, `firestore_data_prefetch`, unified auth edges — see `FIRESTORE_LAUNCH_FLOWS.md`.
2. Apply **000014–000018** on staging/RDS per `DEPLOY_ORDER.md`.
3. Start local Supabase (`npx supabase start`) before Docker integration tests.
