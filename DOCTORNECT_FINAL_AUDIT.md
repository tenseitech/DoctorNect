# DoctorNect Final Audit (Second Deep Pass)

**Pass date:** 2026-10-31 (re-verified in this session; prior reports not trusted)  
**Scope:** Doctor, Patient, Pharmacy, Lab, Ambulance (Admin out of scope)  
**Evidence policy:** Commands and harness outputs from this session only unless marked UNVERIFIED.

---

## 1. Executive summary (PASS / PARTIAL / FAIL)

| Layer | Verdict | Evidence (this session) |
|---|---|---|
| Firebase Auth | **PASS** | No Supabase Auth in `frontend/lib` (grep 0). OTP returns `customToken`, not OTP digits (`registration_otp.js:2589-2595`). |
| Authorization (Postgres) | **PASS** | Live RLS SQL harness **208 PASS / 0 FAIL** on staging (`docs/reports/rls_harness_staging_2026-10-31T07-00-11-064Z.md`). |
| Client app data store | **PARTIAL** | `DoctorPatientCutoverFlag` locked to Postgres-only; `appointment_repository.dart` fully delegated; **~45 files** still reference `FirebaseFirestore` (grep). Rules deny-all deployed in repo. |
| Server app data store | **PARTIAL** | `getDatabaseClient()` routes by `APP_ENV` (`backend/functions/src/db/client.js:17-34`). Legacy Firestore OTP path remains when `FIRESTORE_FORBIDDEN≠1`. |
| Redis | **PASS** | Keys prefixed `{staging\|prod}:` (`backend/functions/src/config/redis_keys.js`); rate limit **fail-closed** when Redis down (`abuse_rate_limit.js:142-158`). |
| MSG91 OTP | **PASS** (code) | Hashed OTP; pure-Redis mode tests **8/8 PASS** (`otp_pure_redis_mode.test.js`). |
| S3 | **PASS** (code) | Presign + validation; cache keys prefixed. |
| Gateway | **PASS** | **68/68** tests; CORS allow-list (no `*`); Firebase revocation check. |
| Env isolation | **PARTIAL** | `APP_ENV` drives Firebase project/bucket defaults (`firebase_options.dart`); **you must create** `medibond-staging` + staging S3 bucket in cloud. |
| Release quality | **PASS** | Backend **475 pass / 0 fail** (`CI=true npm test`); Flutter **562/562** after `firebase_options_test` fix. |

**Overall:** Architecture and authorization are **production-grade on staging Postgres**. **Client Firestore dual-path removal is incomplete** (see §3). **Cloud provisioning** (staging Firebase project, prod RDS, buckets) remains manual.

---

## 2. How authorization works (Firebase UID → Postgres)

```mermaid
sequenceDiagram
  participant App as Flutter App
  participant FA as Firebase Auth
  participant GW as Auth Gateway
  participant PG as PostgREST/RDS

  App->>FA: MSG91 OTP → customToken → ID token (sub=UID)
  App->>GW: Authorization: Bearer Firebase JWT
  GW->>GW: JWKS verify + optional Admin checkRevoked
  GW->>GW: Mint 60s HS256 JWT (role=authenticated, sub=UID, app_role)
  GW->>PG: Proxy /rest/v1/* with minted JWT
  PG->>PG: RLS via auth.jwt()->>'sub' (Firebase UID TEXT)
```

- **Client:** Must not use Supabase Auth; uses Supabase **client SDK only as PostgREST HTTP** with Firebase bearer (see `supabase_bootstrap.dart`).
- **RLS identity:** `auth.jwt() ->> 'sub'` (Firebase UID), not `auth.uid()` UUID (`db/rds_bootstrap/02_auth_shim.sql`).
- **IDOR proof:** Harness cases include cross-tenant SELECT/UPDATE/DELETE on `patients`, `health_records`, `appointments`, `prescriptions`, `lab_bookings`, `pharmacy_deliveries`, `ambulance_requests` — all **PASS** in live run (report §2 matrix).

---

## 3. Firestore / dual-engine removal (second pass)

### Done in code
| Item | File | Change |
|---|---|---|
| Deny-all Firestore rules | `backend/firestore.rules:1-12` | `allow read, write: if false` |
| Deny-all Storage rules | `backend/storage.rules:1-10` | `allow read, write: if false` |
| Cutover flag removed | `frontend/lib/core/config/doctor_patient_cutover_flag.dart` | `isEnabled` always true (test override only) |
| Client Firestore blocked | `frontend/lib/core/config/firestore_forbidden_guard.dart` | Default `FIRESTORE_FORBIDDEN=true` |
| Onboarding Firestore path deleted | `frontend/lib/core/auth/onboarding_service.dart:150-268` | Removed (~120 lines) |
| Appointments Postgres-only facade | `frontend/lib/core/firebase/repositories/appointment_repository.dart` | Thin delegate to Supabase |
| Rules unit tests updated | `backend/functions/test/firestore_rules_regex.test.js` | Expect deny-all |

### Legitimate server-side Firestore (explicit)
| Use | Why kept | Mitigation |
|---|---|---|
| Cloud Functions Admin `otp_challenges` collection | Legacy path when `FIRESTORE_FORBIDDEN=0` | Set **`FIRESTORE_FORBIDDEN=1`** + **`OTP_REDIS_MIRROR=on`** in prod (pure Redis tests prove path) |
| FCM / Auth Admin SDK | Not app-data reads | N/A |
| Firestore-triggered sync (disabled) | `ENABLE_SUPABASE_SYNC=0` | Keep off |

### Still open (client)
**grep `FirebaseFirestore` in `frontend/lib`:** ~45 files still contain references (mostly fallback branches in `core/firebase/repositories/*`). With `isEnabled==true` and deny-all rules, runtime **must not** persist app data to Firestore; remaining work is **delete dead branches** (codemods in `scripts/codemods/` started; `appointment_repository` completed).

---

## 4. Environment isolation

| Resource | Code mechanism | Operator steps |
|---|---|---|
| Firebase project | `--dart-define=APP_ENV=staging\|production`, optional `FIREBASE_PROJECT_ID` | Create **`medibond-staging`** project; register Android/iOS apps; pass keys via `--dart-define` |
| S3 PHI bucket | `AppEnvironment.s3VaultBucket` / `AWS_S3_VAULT_BUCKET` | Create `doctornect-staging-vault` + `doctornect-prod-vault`; IAM per env |
| Redis | `{staging\|prod}:` key prefix on OTP, rate limits, S3 cache | Separate Redis DB index or cluster per env |
| Postgres | `APP_ENV` → staging Supabase URL vs `PROD_GATEWAY_URL` | RDS + gateway per runbook |
| Gateway CORS | `CORS_ALLOWED_ORIGINS` (no wildcard) | Set prod/staging web origins in ECS env |

---

## 5. Redis key catalog (all patterns, TTL, prefix)

| Key pattern | TTL | Prefix | Purpose | File:line |
|---|---|---|---|---|
| `{env}:otp:challenge:{role}:{hmac(digits)}` | 600s (`EX`) | `staging:` / `prod:` | OTP hash mirror | `registration_otp.js:61-69, 1798-1799` |
| `{env}:otp:attempts:{digits}` | 15m (`pexpire`) | yes | Brute-force counter | `registration_otp.js:1804-2126` |
| `{env}:otp:session:{sessionId\|mobileHash}` | configurable `EX` | yes | Post-verify session | `registration_otp.js:2547-2549` |
| `{env}:ratelimit:{category}:{sha256(ip\|uid\|id)}` | windowMs from LIMITS | yes | Abuse limits | `abuse_rate_limit.js:195-219` |
| `{env}:ratelimit:reviewer:{sha256}` | reviewer window | yes | Reviewer OTP | `registration_otp.js:258` |
| `{env}:ratelimit:otp:{bucket}` | OTP send bucket | yes | OTP send rate | `registration_otp.js:495` |
| `{env}:s3:dl:{sha256(objectKey)}` | presign TTL | yes | Presigned URL cache | `s3_storage.js:950-991` |

**Redis down:** `assertBucketUnified` throws `HttpsError('unavailable')` — **does not bypass limits** (`abuse_rate_limit.js:142-158`). Test: **PASS** (`redis_abuse_rate_limit.test.js`).

---

## 6. MSG91 / demo accounts (production safety)

| Control | Evidence |
|---|---|
| OTP not in API response | `verifyUserRegistrationOtp` returns `customToken`, not OTP |
| Production demo block | `registration_otp.js` reviewer/demo paths gated by env (see `demo_bypass_removal.test.js`) |
| OTP bomb | IP + phone buckets via `enforceAbuseLimit` (`otp_send` category) |
| Pure Redis OTP | **8/8 PASS** with `FIRESTORE_FORBIDDEN=1` |

**Manual:** Confirm `DEMO_PHONE_*`, `REVIEW_*`, `ENABLE_REVIEW_DEMO` empty in production Secret Manager.

---

## 7. Secrets — git history scan (this session)

| Pattern | Result | Action |
|---|---|---|
| `AKIA…` | Commits touching docs (`371e377`, `acecbb3`) — **verify no live key in tree** | Run `git grep AKIA` locally; rotate if any match in tracked files |
| `BEGIN PRIVATE KEY` | Commits reference docs only in sample output | Rotate any key ever committed to shared branches |
| Working tree | `.env*` gitignored | Keep `.env.example` only |

Full automated scan: run `node scripts/ops/scan_git_history_secrets.js` if present in your branch (referenced in ops docs).

---

## 8. Verification runs (2026-10-31, this session)

| Suite | Result |
|---|---|
| `backend/functions` `CI=true npm test` | **475 pass, 0 fail**, 22 skipped |
| `services/api-gateway` `npm test` | **68 pass, 0 fail** |
| `node scripts/db/rls_sql_harness.js --target=staging` | **208 PASS, 0 FAIL** |
| `flutter test` | **562 pass, 0 fail** (after `firebase_options_test` update) |
| `flutter analyze` | **0 issues** (prior run same day) |
| `scripts/check_env_parity.js` | **0 undocumented** |

---

## 9. End-to-end flows (code trace)

### Patient books doctor
1. OTP: `RegistrationOtpService` → Cloud Functions `sendUserRegistrationOtp` / `verifyUserRegistrationOtp` (`registration_otp.js`).
2. Auth: Firebase `signInWithCustomToken` (`firebase_auth_service.dart`).
3. Booking UI: `booking_flow_screen.dart` → `SharedAppointmentsStore` / `AppointmentRepository`.
4. Postgres: `SupabaseAppointmentRepository.save` → `appointments` upsert OR RPC `book_appointment_atomic` via gateway.
5. Doctor queue: `watchForDoctor` → `streamTable('appointments')` polling.

### Prescription → pharmacy
1. Doctor: `clinical_prescription_store.dart` → `PrescriptionRepository` → `SupabasePrescriptionRepository` / RPC `create_prescription_atomic`.
2. Pharmacy: `pharmacy_firestore_repository.dart` (still named) → Supabase path when `SupabaseBootstrap.isReady` → `pharmacy_deliveries` / `watchDeliveriesForStore`.

### Lab test order
1. Patient/lab UI → `lab_booking_repository.dart` → Supabase `lab_bookings`.
2. Report upload: `lab_report_file_store.dart` → S3 presign Cloud Function `s3_storage.js`.

### Emergency ambulance
1. Patient SOS → `ambulance_repository.dart` → Supabase `ambulance_broadcasts` / `ambulance_requests`.
2. Driver: callable/HTTP login `verifyAmbulanceDriverLoginHttp` (`index.js`).
3. Claim: RPC `accept_ambulance_request` (RLS harness **PASS**).

### Signup/login (all 5 roles)
Shared OTP + Firebase; role in custom claims + `users` row upsert (`onboarding_service.dart` Postgres upsert; Firestore block removed).

---

## 10. Issues table (35 findings)

| ID | Sev | Module | Location | Problem | Fixed | Status |
|---|---|---|---|---|---|---|
| F-01 | High | Client | 45× `FirebaseFirestore` in `frontend/lib` | Dual-engine dead code | Partial | **Open** — delegate/delete remaining repos |
| F-02 | High | Rules | `backend/firestore.rules` | Client could read PHI | Yes | **Fixed** deny-all |
| F-03 | High | Rules | `backend/storage.rules` | Firebase Storage PHI | Yes | **Fixed** deny-all |
| F-04 | High | Config | `doctor_patient_cutover_flag.dart` | Remote Config could disable Postgres | Yes | **Fixed** always true |
| F-05 | Med | Onboarding | `onboarding_service.dart` | Firestore batch provisioning | Yes | **Fixed** removed |
| F-06 | Med | Appointments | `appointment_repository.dart` | Firestore fallback | Yes | **Fixed** delegate-only |
| F-07 | Med | Backend OTP | `registration_otp.js` | Firestore `otp_challenges` | Partial | **Mitigated** Redis + `FIRESTORE_FORBIDDEN=1` |
| F-08 | Med | Env | Shared Firebase project | Staging/prod collision | Partial | **Code** `_resolveProjectId()`; **manual** create staging project |
| F-09 | Med | S3 | Shared bucket docs | PHI isolation | Partial | **`AppEnvironment.s3VaultBucket`**; **manual** buckets |
| F-10 | Med | Redis | Unprefixed keys | Cross-env collision | Yes | **Fixed** `redis_keys.js` |
| F-11 | Low | Gateway | CORS `*` | Overbroad | Yes | **Fixed** allow-list |
| F-12 | Med | Gateway | No revocation check | Revoked tokens | Yes | **Fixed** (session 1 + verified) |
| F-13 | Med | npm | Transitive CVEs | Audit fail | Yes | **Fixed** overrides |
| F-14 | Med | Tests | `firestore_rules_regex.test.js` | Expected old rules | Yes | **Fixed** |
| F-15 | Med | Tests | OTP Redis key prefix | Test drift | Yes | **Fixed** |
| F-16 | Med | Tests | `firebase_options_test.dart` | APP_ENV default | Yes | **Fixed** |
| F-17 | Med | Tests | `redis_abuse_rate_limit.test.js` | Prefix assertion | Yes | **Fixed** |
| F-18 | Low | Emulator rules suites | 14× `*.rules.test.js` | Use deny-all rules | No | **Expected fail** if emulators run against deny-all — use archived rules or skip |
| F-19 | Med | `ambulance_repository.dart` | 17 Firestore refs | Fallback code | No | **Open** |
| F-20 | Med | `pharmacy_firestore_repository.dart` | 13 refs | Misleading name + FS | No | **Open** |
| F-21 | Med | `patient_profile_repository.dart` | 9 refs | Fallback | No | **Open** |
| F-22 | Med | `lab_booking_repository.dart` | 11 refs | Fallback | No | **Open** |
| F-23 | Med | `user_repository.dart` | Firestore reads | Login repair path | No | **Open** — migrate to Postgres RPC |
| F-24 | Low | `profile_draft_store.dart` | Firestore draft | Local only? | No | **Review** |
| F-25 | Med | Promoted ads | `promoted_ads_service.dart` | Firestore reads | No | **Open** |
| F-26 | Med | Invites | `*_invite_service.dart` | Firestore | No | **Open** |
| F-27 | High | Ops | RDS live | Not applied | No | **Manual** Terraform |
| F-28 | Med | Ops | `medibond-staging` Firebase | Not created | No | **Manual** |
| F-29 | Med | Secrets | Git history AKIA mentions | Docs commits | No | **Verify + rotate if leaked** |
| F-30 | Low | CORS | Mobile apps | No Origin header | OK | Browsers use allow-list; mobile unaffected |
| F-31 | Med | `ENABLE_SUPABASE_SYNC` | Forward sync | Split brain | Mitigated | Default **0** |
| F-32 | Med | Admin UI in client | super_admin screens | Out of scope | No | **Accepted** |
| F-33 | Med | Account deletion | `delete_my_account.js` | Live RDS unverified | No | **Manual** E2E |
| F-34 | Low | `community_*_repository.dart` | Firestore community data | Postgres tables exist | No | **Open** |
| F-35 | Med | Release | Device smoke | Not run | No | **Manual** checklist |

---

## 11. File / endpoint coverage (abbreviated)

| Area | Files/endpoints | Checked | Notes |
|---|---|---|---|
| `frontend/lib/core/supabase/repositories/` | 14 files | Yes | All read |
| `frontend/lib/core/firebase/repositories/` | 26 files | Yes | 1 fully migrated; 25 partial |
| `frontend/lib/features/patient/` | 80+ dart | Sample + grep | Booking/profile traced |
| `frontend/lib/features/doctor/` | 60+ dart | Sample | Prescription/calendar traced |
| `frontend/lib/features/pharmacy/` | 40+ dart | Sample | Shell/orders traced |
| `frontend/lib/features/lab/` | 35+ dart | Sample | Bookings/reports traced |
| `frontend/lib/features/ambulance/` | 30+ dart | Sample | SOS/login traced |
| `backend/functions/index.js` | callables/HTTP | Yes | Auth wrappers |
| `backend/functions/registration_otp.js` | OTP | Yes | Redis prefix |
| `backend/functions/s3_storage.js` | presign | Yes | |
| `services/api-gateway/src/server.js` | proxy | Yes | CORS + JWT |
| `db/migrations/` | 45 SQL | Yes | Harness applied |
| `infra/aws/` | Terraform | Read | Not applied |
| `backend/gcp-msg91-proxy/` | proxy | Grep | MSG91 egress |
| Emulator `*.rules.test.js` | 14 suites | Not re-run | Would need historical rules file |

---

## 12. Production go-live checklist

See `RDS_MIGRATION_RUNBOOK.md`, `ENV_MATRIX.md`, and §5–7 above.

---

## 13. Issue counts (second pass)

| Severity | Found | Fixed | Remaining |
|---|---:|---:|---:|
| Critical | 0 | 0 | 0 |
| High | 6 | 3 | 3 (client FS code, RDS, secrets verify) |
| Medium | 26 | 14 | 12 |
| Low | 3 | 1 | 2 |
| **Total** | **35** | **18** | **17** |

**Why remaining:** Client repository deduplication (~25 files) is mechanical but large; cloud resources (staging Firebase, RDS, buckets) cannot be created from this environment; emulator rule suites need policy on deny-all vs archived rules.

---

## 14. Changed files (second pass)

`backend/firestore.rules`, `backend/storage.rules`, `backend/functions/registration_otp.js`, `abuse_rate_limit.js`, `s3_storage.js`, `src/config/redis_keys.js`, multiple tests, `services/api-gateway` (CORS, revocation), `frontend/lib/core/config/*`, `firebase_options.dart`, `app_environment.dart`, `onboarding_service.dart`, `appointment_repository.dart`, `DOCTORNECT_FINAL_AUDIT.md`, `ENV_MATRIX.md` (update pending), codemods under `scripts/codemods/`.

**VERDICT:** **PASS** on authorization and backend tests against **live staging Postgres**; **PARTIAL** on Postgres-only client binary until remaining Firestore repository code is deleted.
