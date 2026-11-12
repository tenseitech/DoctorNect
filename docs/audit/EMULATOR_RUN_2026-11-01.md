# `npm run test:emulators` run (2026-11-01)

**Command:** `cd backend/functions && npm run test:emulators`  
**Emulator project:** `demo-doctornect-test` (single `firebase emulators:exec` wrapper)  
**Scope:** 13 test modules only (not full `npm test` under emulators).

## Totals (this run)

| Metric | This run | Baseline file (`baseline_failing_tests.txt`) |
|--------|----------|---------------------------------------------|
| Tests | **302** | **735** (full suite via `npm test --prefix backend/functions`) |
| Pass | **170** | 591 |
| Fail | **132** | 139 |
| Skip | **0** | 5 |

Baseline is **not** directly comparable line-for-line: baseline captured **all** function tests under emulators; `test:emulators` runs **13** rules/emulator files only.

## Project ID / PERMISSION_DENIED pattern

Several suites hard-code **different** Firebase project IDs than the exec wrapper (`demo-doctornect-test`), for example:

- `demo-doctornect-claims-rules` — `profile_claims_rules.test.js`
- `demo-doctornect-reviews` — `firestore_reviews.rules.test.js`
- `demo-doctornect-s3-rules` — `firestore_s3_rules.test.js`
- `demo-doctornect-dir-appt-rules` — `firestore_directory_and_appointments.rules.test.js`
- `demo-doctornect-promoted-rules` — `promoted_ads_verification.test.js`
- `demo-doctornect-slots` — `doctor_slots_emulator.test.js`
- `demo-doctornect-kyc` — storage KYC / live app path tests
- `demo-doctornect-deadletters-rules` — `sync_dead_letters.rules.test.js`

Log shows mass **`PERMISSION_DENIED`** on Firestore **Write** during baseline seeding (e.g. `client_read_replay.rules.test.js`, `client_payload_replay.rules.test.js`), consistent with **deny-all / tightened rules** vs tests that expect to seed documents.

**Suites with top-level ✖ (module/suite names):**

- `HEAD Rules Replay Suite (Real Baseline)`
- `741cb46 Client Payload Replay Suite on Real Baseline (HEAD vs Live)`
- `Baseline Comparison: WITHOUT createdVia …`
- `Replay against HEAD Rules`
- `directory list rules`
- `promotedAds provider role rules`
- `patient appointment create`
- `appointment update key restrictions`
- `tightened appointment rules`
- `prescription, delivery, and ambulance party rules`
- `community catalog create bounds`
- `firestore.rules: promotedAds & razorpayPayments security rules`
- `syncDeadLetters Rules: Super Admin read allowed`
- Many storage KYC / live path tests (`storage/unauthorized`)

## vs baseline failure names

Most failing subtest titles **match** entries already listed in `docs/audit/baseline_failing_tests.txt` (profile claims, payload replay, directory reads, promoted ads, storage KYC, etc.).

**Notable:** this run did **not** execute non-emulator unit tests (Redis, OTP mocks, Supabase webhook, etc.), so **no new signal** on those paths.

**Do not edit** `firestore.rules` / `storage.rules` / indexes on this branch until baseline intent is agreed.

Raw log: `docs/_emulator_test_run.log` (gitignored pattern `docs/_emulator_test_run.log` may apply — local only).
