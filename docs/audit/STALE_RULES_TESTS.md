# Stale Firestore / Storage rules emulator tests

**Status:** documentation only — **do not** edit `backend/firestore.rules`, `storage.rules`, indexes, or test bodies on this pass.

**Current rules (HEAD):** `backend/firestore.rules` is **deny-all** for all paths:

```7:9:backend/firestore.rules
    match /{document=**} {
      allow read, write: if false;
    }
```

Emulator suites that **seed** collections (`users`, `doctors`, `appointments`, replay baselines, etc.) receive **`PERMISSION_DENIED`** on writes. That matches the 2026-11-01 `npm run test:emulators` run (`docs/audit/EMULATOR_RUN_2026-11-01.md`): **132 fail / 170 pass / 302 tests** in the 13-module bundle.

**Baseline reference:** `docs/audit/baseline_failing_tests.txt` (~139 failures under full `npm test` + emulators, 735 tests).

---

## Failing suites (module / top-level names)

| Suite / module | Emulator project ID (when hard-coded) | Primary failure mode |
|----------------|----------------------------------------|----------------------|
| `profile_claims_rules.test.js` | `demo-doctornect-claims-rules` | Seed writes denied |
| `firestore_reviews.rules.test.js` | `demo-doctornect-reviews` | Seed + review rules |
| `firestore_s3_rules.test.js` | `demo-doctornect-s3-rules` | Seed writes denied |
| `firestore_directory_and_appointments.rules.test.js` | `demo-doctornect-dir-appt-rules` | Directory / appointment seeds |
| `promoted_ads_verification.test.js` | `demo-doctornect-promoted-rules` | `promotedAds` seeds |
| `doctor_slots_emulator.test.js` | `demo-doctornect-slots` | Slot documents |
| `storage_doctor_kyc.rules.test.js` | `demo-doctornect-kyc` | Storage + Firestore setup |
| `storage_provider_kyc.rules.test.js` | `demo-doctornect-kyc` | Same |
| `storage_live_app_paths.rules.test.js` | `demo-doctornect-kyc` | Live path uploads |
| `client_payload_replay.rules.test.js` | wrapper `demo-doctornect-test` (replay paths vary) | Baseline seed **Write** denied |
| `client_read_replay.rules.test.js` | wrapper `demo-doctornect-test` | Read replay after failed seed |
| `sync_dead_letters.rules.test.js` | `demo-doctornect-deadletters-rules` | `syncDeadLetters` seeds |
| `sync_to_firestore_emulator.test.js` | `demo-doctornect-test` | Sync edge + Firestore writes |

**Representative failing subtest themes** (from baseline + 2026-11-01 run):

- HEAD / client payload & read replay suites
- Profile claims registration and self-approve denial cases
- Directory list rules (doctors, labs, pharmacies, ambulances)
- Promoted ads provider rules
- Patient appointment create / update restrictions
- Prescription, delivery, ambulance party rules
- Community catalog create bounds
- Storage KYC unauthorized paths

---

## Secondary issue: project ID mismatch

Several files start their **own** emulator project IDs while `test:emulators` wraps all 13 files under **`demo-doctornect-test`**. Even with permissive rules, some tests assume isolated project IDs from `package.json` per-suite scripts. Align wrapper project ID with each suite **or** refactor tests to use the exec project — separate from deny-all.

---

## Proposal: update vs retire

| Category | Proposal |
|----------|----------|
| **Replay / baseline comparison** (`client_*_replay`, directory/promoted/appointment rules tied to historical rules files) | **Retire or quarantine** behind `@skip` / delete after cutover sign-off. They validate **old** Firestore security models, not postgres-only deny-all. |
| **Profile claims / registration rules** | **Retire** if Auth claims are fully Postgres-backed and Firestore `users`/`doctors` writes are permanently forbidden. |
| **Storage KYC rules tests** | **Update** only if Storage rules still govern KYC objects in production; otherwise **retire** with pointer to S3/gateway tests. |
| **`sync_to_firestore_emulator.test.js` / `sync_dead_letters.rules.test.js`** | **Retire** when reverse Firestore sync is removed from product (postgres-only architecture). |
| **`doctor_slots_emulator.test.js`** | **Replace** with Supabase/RPC or integration tests if slots live only in Postgres. |

**Recommended sequence (future work, not this branch):**

1. Product decision: Firestore rules remain **deny-all** permanently → bulk **retire** emulator rules suite with note in `EMULATOR_TESTS.md`.
2. If any Firestore path must stay (e.g. FCM token mirror only), **narrow** new rules + **small** targeted rules tests — do not restore full PHI rule surface.
3. Keep **`npm test`** default **without** emulators for unit coverage; keep `test:emulators` as optional regression until suites are retired.

**Do not** loosen `backend/firestore.rules` to make these tests pass without explicit security review — deny-all is intentional for postgres-only cutover.
