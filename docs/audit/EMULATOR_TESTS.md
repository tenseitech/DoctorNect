# Firestore / Storage emulator tests

Default `npm test` **does not** start emulators. `test/setup_env.js` clears `FIRESTORE_EMULATOR_HOST` so emulator-heavy files register **skipped** placeholders (22 skips in the 474/0/22 baseline).

## Run all emulator-gated modules

From `backend/functions`:

```bash
npm run test:emulators
```

This runs `firebase emulators:exec --only firestore,storage` once, then executes **13 test modules** (17 skipped subtests in default `npm test` when emulators are off):

| Module | Notes |
|--------|--------|
| `test/profile_claims_rules.test.js` | Firestore rules — profile claims |
| `test/firestore_reviews.rules.test.js` | Reviews rules |
| `test/firestore_s3_rules.test.js` | S3 metadata rules |
| `test/firestore_directory_and_appointments.rules.test.js` | Directory + appointments |
| `test/promoted_ads_verification.test.js` | Promoted ads + rules (large) |
| `test/doctor_slots_emulator.test.js` | Parallel booking race |
| `test/storage_doctor_kyc.rules.test.js` | Storage KYC |
| `test/storage_provider_kyc.rules.test.js` | Provider KYC |
| `test/storage_live_app_paths.rules.test.js` | Live app storage paths |
| `test/client_payload_replay.rules.test.js` | Payload replay |
| `test/client_read_replay.rules.test.js` | Read replay |
| `test/sync_dead_letters.rules.test.js` | Sync DLQ rules |
| `test/sync_to_firestore_emulator.test.js` | Sync bridge emulator |

**Requirements:** JDK 21+ for Firestore emulator, Firebase CLI, no conflicting emulator on ports 8080/9199.

`test:emulators` does **not** use `test/setup_env.js` so `firebase emulators:exec` can inject emulator host variables.
