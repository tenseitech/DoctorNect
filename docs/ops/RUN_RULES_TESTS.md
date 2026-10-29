# Running Firestore & Cloud Storage Rules Tests

## Overview
This document specifies the procedure for executing the security rules and emulator integration test suite for DoctorNect's Firebase services (Cloud Firestore and Firebase Storage).

## Prerequisites
1. **Java Runtime (JDK / JRE >= 17)**:
   Firebase Local Emulator Suite requires Java to emulate Firestore and Cloud Storage.
   - Verified on host: `openjdk version "21.0.12" 2026-07-21 LTS / OpenJDK 64-Bit Server VM Temurin-21.0.12.1+1`.
   - To verify locally:
     ```bash
     java -version
     ```
2. **Firebase Tools CLI**:
   Run via `npx firebase-tools` or install globally via `npm i -g firebase-tools`.

## Test Execution

### Single Command (All Rules + Emulator Tests)
From the repo root:
```bash
npm run test:rules
```
Or from `backend/functions/`:
```bash
npx firebase-tools emulators:exec --only firestore,storage --project demo-doctornect-test "node --test test/*.rules.test.js test/*_emulator.test.js"
```

### Covered Test Suites
The following 11 rules and emulator test suites execute against the local emulator instance:
1. `test/client_payload_replay.rules.test.js`
2. `test/client_read_replay.rules.test.js`
3. `test/doctor_slots_emulator.test.js`
4. `test/firestore_directory_and_appointments.rules.test.js`
5. `test/firestore_reviews.rules.test.js`
6. `test/firestore_s3_rules.test.js`
7. `test/profile_claims_rules.test.js`
8. `test/storage_doctor_kyc.rules.test.js`
9. `test/storage_live_app_paths.rules.test.js`
10. `test/storage_provider_kyc.rules.test.js`
11. `test/sync_dead_letters.rules.test.js`
12. `test/sync_to_firestore_emulator.test.js`

When executed outside the emulator environment (e.g. basic `node --test`), these suites automatically detect missing emulator ports and gracefully mark cases as skipped to allow unit testing in non-Java environments.
