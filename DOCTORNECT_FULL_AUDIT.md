# DoctorNect — Full Security & Production Readiness Audit

**Date:** 2026-11-03  
**Scope:** Doctor, Patient, Pharmacy, Lab, Ambulance modules only (Admin UI out of scope; admin cross-exposure noted where shared backend/RLS affects all roles).  
**Method:** Code and config review on branch `chore/dedupe-structure-audit`; `flutter analyze` (0 issues); backend `npm test` (494 pass / 0 fail / 22 skip); `npm audit` (0 vulnerabilities in `backend/functions`). Prior reports in `docs/` were used as hints only and re-checked.

**Assumption (safest):** Production PostgreSQL target is AWS RDS via `PROD_GATEWAY_*`; staging is Supabase. Live fleet may lag this branch (see `docs/audit/APP_BACKEND_CONTRACT.md` gaps G1–G3).

---

## 1. Executive Summary

**Overall Rating: 6.5 / 10** *(was 5.5 before Phase 2 auto-fixes in this session)*

The codebase shows a deliberate **Postgres-primary** direction (deny-all Firestore rules, Supabase repositories, no Firestore triggers in `index.js`), but **production client defaults (`FIRESTORE_FORBIDDEN=true`) still conflict with remaining direct Firestore SDK usage** in ambulance, drafts, invites, and ads. Backend OTP/login **Critical `isDemoPhone` bug is fixed**; **`bookAppointment` now resolves caller via Supabase** when cutover is primary. PostgreSQL RLS **`doctors_select` regression has a new idempotent migration** (owner must apply on staging/RDS). Deploy hygiene still blocks releases (**Check 0 REDIS_* overlap**). RDS production cutover, bucket IAM, and Play Store reviewer flows remain **partially documented, not fully verified in this pass**.

**Production-readiness verdict:** **READY WITH CONDITIONS** (fix Critical/High blockers, deploy `cleanupPendingRegistration`, resolve Check 0, validate RLS on staging, complete ambulance/doctor Firestore excision or explicit exceptions).

| Severity | Count (Issues Register) |
|----------|-------------------------|
| Critical | 1 *(SEC-001 fixed; register had 1 verified Critical)* |
| High | 12 *(2 auto-fixed in repo; several need deploy/migration apply)* |
| Medium | 14 |
| Low | 8 |
| Info | 6 |

---

## 2. Scorecard Table

| Area | Score /10 | Status | Top concern |
|------|-----------|--------|-------------|
| A. Architecture & migration | 5 | Warn | Ambulance + doctor still use real Firestore SDK under default forbidden guard |
| B. Auth & authorization | 7 | Warn | Booking still reads doctor/slots from Firestore in callable |
| C. Database (Postgres) | 7 | Warn | Apply `20261103000011` / `20261103000012` on staging/RDS |
| D. Redis | 7 | Pass | Env-slug keys; OTP mirror optional; not source of truth |
| E. S3 / files | 7 | Pass | Deny-all Storage rules; presigned path in functions |
| F. Security | 5 | Fail | Check 0 overlap; history/pre-push example templates |
| G. Backend / API | 6 | Warn | Mixed Firestore/Postgres in callables; secret binding drift |
| H. Mobile app | 6 | Warn | 13 known failing tests; Firestore pockets |
| I. Code quality & hygiene | 7 | Pass | Flutter analyze clean; backend tests green |
| J. Performance & scale | 6 | Warn | Unbounded queries UNVERIFIED; ambulance Firestore hot path |
| K. Production / go-live | 4 | Fail | G2 callable not deployed; RDS UNVERIFIED |
| **Doctor** | 6 | Warn | `persist()` uses Supabase when cutover; notification prefs still Firestore |
| **Patient** | 7 | Pass | Supabase-primary booking when cutover flag on |
| **Pharmacy** | 7 | Pass | Facade → Supabase |
| **Lab** | 7 | Pass | Facade → Supabase |
| **Ambulance** | 4 | Fail | `ambulance_repository.dart` Firestore-heavy |

---

## 3. Issues Register

#### [SEC-001] Login OTP verify calls undefined `isDemoPhone`
- Severity: Critical
- Module(s): All
- Location: `backend/functions/registration_otp.js:2596–2603`
- Problem: `isDemoPhone` is invoked but not defined or exported (`demo_bypass_removal.test.js:53` expects it removed).
- Impact: Login OTP success path can throw `ReferenceError`; users cannot complete mobile login after verify.
- Evidence: `const isDemoAccount = await isDemoPhone(digits, loginRole);` — no `function isDemoPhone` in repo grep.
- Fix (WHAT): Remove demo branch or replace with no-op `false` after demo removal.
- How to fix (STEP BY STEP): 1) Delete lines 2596–2603 or set `isDemoAccount = false` with comment referencing demo removal. 2) Run `npm test -- test/demo_bypass_removal.test.js test/otp_send_verify_roundtrip.test.js`. 3) Manual OTP login smoke.
- How to verify: `npm test`; login flow integration test.
- Effort: S
- Type: Auto-fixable by Cursor
- Status: **FIXED** — dead demo branch removed (`registration_otp.js`)

#### [SEC-002] Broad authenticated read on `public.doctors`
- Severity: High
- Module(s): Doctor, Patient
- Location: `db/migrations/20261102000001_round6_guards_and_kyc.sql` (~253–255) — policy `doctors_select` `USING (true)` for `authenticated`
- Problem: Any signed-in user can SELECT all doctor rows (PII/directory leakage vs least privilege).
- Impact: IDOR-style data exposure via PostgREST; violates healthcare least-privilege expectation.
- Evidence: Migration policy text (grep `doctors_select` in round6 file).
- Fix: Replace `USING (true)` with verified-directory predicate (e.g. `verified = true` OR owner OR admin helper).
- How to fix: New migration `20261103*_doctors_select_least_privilege.sql` with `DROP POLICY` + `CREATE POLICY` — do not edit applied migrations.
- How to verify: `scripts/test_live_rls_idor.js` or policy unit tests; patient cannot read unrelated doctor private fields.
- Effort: M
- Type: Needs manual action (migration apply on staging/RDS)
- Status: **PARTIAL** — migration added `db/migrations/20261103000011_doctors_select_least_privilege.sql`; not applied to live DB in this session

#### [SEC-003] Deploy blocked: plain `REDIS_*` overlaps Secret Manager bindings
- Severity: High
- Module(s): All
- Location: `scripts/predeploy_secret_check.js` Check 0; `backend/functions/index.js:458,511` + `src/config/redis.js:21–23`
- Problem: Local deploy `.env` sets `REDIS_HOST/PORT/PASSWORD` while code binds same names as secrets when `OTP_REDIS_MIRROR=on`.
- Impact: Cannot deploy functions until fixed; risk of secrets in upload bundle if ignored.
- Evidence: `node scripts/predeploy_secret_check.js` exit 1 (documented in `docs/audit/PLAIN_VS_SECRET_OVERLAP.md`).
- Fix: Remove plain Redis names from deploy `.env`; use Secret Manager + `.env.local` for emulator.
- How to verify: Check 0 exit 0.
- Effort: M
- Type: Needs manual action (owner edits deploy `.env` / SM versions — not in repo)

#### [SEC-004] `cleanupPendingRegistration` not on deployed fleet
- Severity: High
- Module(s): Patient, All
- Location: `docs/audit/APP_BACKEND_CONTRACT.md` G2; `backend/functions/index.js:567–579`
- Problem: App branch calls callable; Oct baseline export list omits it.
- Impact: Registration rollback leaves orphan Supabase rows; RLS blocks client DELETE.
- Evidence: Contract gap table G2/G3.
- Fix: Canary deploy callable after Check 0 (`docs/audit/RELEASE_GATE.md` Gate 3).
- How to verify: Callable listed in console; smoke `{ok,cleaned}`.
- Effort: M
- Type: Needs manual action (deploy)

#### [ARCH-001] Ambulance module still Firestore-centric on client
- Severity: High
- Module(s): Ambulance
- Location: `frontend/lib/core/firebase/repositories/ambulance_repository.dart` (multiple `.collection(` usages, e.g. ~88–91, 568–614, 735–868 per explore audit)
- Problem: Real Firestore reads/writes while `FirestoreForbiddenGuard` default true (`firestore_forbidden_guard.dart:9–10`).
- Impact: Driver/booking flows fail or throw at runtime in release builds.
- Evidence: Grep count 45 `.collection(` in file; guard default true.
- Fix: Complete Supabase ambulance repository paths; remove Firestore fallbacks or gate behind explicit dev-only flag.
- How to verify: `flutter test` ambulance tests; manual driver flow with `FIRESTORE_FORBIDDEN=true`.
- Effort: L
- Type: Auto-fixable by Cursor (large)

#### [ARCH-002] Doctor profile persisted to Firestore without cutover guard
- Severity: High
- Module(s): Doctor
- Location: `frontend/lib/features/doctor/profile/data/doctor_profile_store.dart:410–413` (`set` on `doctors/{id}`)
- Problem: Writes bypass Supabase-only path when guard forbids Firestore.
- Impact: Profile save fails in production client configuration.
- Evidence: Direct `FirebaseFirestore` write lines cited.
- Fix: Route persist through Supabase doctor repository only; delete Firestore write.
- How to verify: Doctor profile save E2E on staging build.
- Effort: M
- Type: Auto-fixable by Cursor
- Status: **FIXED** — `persist()` uses `SupabaseDoctorRepository.saveDoctorProfileFields` when `DoctorPatientCutoverFlag.isEnabled` (`doctor_profile_store.dart`, `supabase_doctor_repository.dart`)

#### [ARCH-003] Dual appointment sources merged (Supabase + Firestore)
- Severity: Medium
- Module(s): Patient, Doctor
- Location: `frontend/lib/core/.../shared_appointments_store.dart:243–257, 309–338` (per explore)
- Problem: Fallback merge can show stale/wrong data if Firestore deny-all.
- Impact: Duplicate/missing appointments in UI.
- Fix: Single source when `DoctorPatientCutoverFlag` true; remove Firestore fetch branch.
- Effort: M
- Type: Auto-fixable by Cursor

#### [AUTH-001] `bookAppointment` reads role from Firestore only
- Severity: High
- Module(s): Patient
- Location: `backend/functions/appointment_slots.js:513–521`
- Problem: Under Supabase-primary backend (`sync_flags.js:47–51` always true), caller profile may exist only in Postgres.
- Impact: Valid patients denied booking (`permission-denied` profile not found).
- Evidence: `db.collection('users').doc(auth.uid).get()` with no `getDatabaseClient()`.
- Fix: Use `resolveCallerIdentity` / Supabase user row when primary.
- How to verify: `npm test` booking tests + Supabase-primary integration.
- Effort: M
- Type: Auto-fixable by Cursor
- Status: **FIXED** — `resolveCallerIdentity` in `appointment_slots.js:513–527`

#### [AUTH-002] Post-login OTP verify logs mobile suffix (PII in logs)
- Severity: Medium
- Module(s): All
- Location: `backend/functions/registration_otp.js:2615–2618`, `2589–2593`
- Problem: Logs include `mobileLast4`, roles — acceptable; ensure full mobile never logged (spot-check needed).
- Impact: Log aggregation exposure if format changes.
- Fix: Audit all `console.*` in `registration_otp.js` for full mobile/OTP; redact.
- Effort: M
- Type: Auto-fixable by Cursor

#### [AUTH-003] Reviewer fixed OTP path still active when env set
- Severity: Medium
- Module(s): Patient (prod: patient-only)
- Location: `registration_otp.js:129–174`, `2108–2109`; `production_otp_guard.js` (does not block `REVIEW_*`)
- Problem: Play Store review requires bypass; prod must keep `ENABLE_REVIEW_DEMO` off except review window.
- Impact: Fixed OTP login if misconfigured env on production project.
- Fix: Operational — unset `REVIEW_*` after review; monitor env (`docs/audit/REVIEW_OTP_PATHS.md`).
- Effort: S
- Type: Needs manual action

#### [DB-001] Missing index on `patients.primary_doctor_id` / `invited_doctor_id`
- Severity: Medium
- Module(s): Doctor, Patient
- Location: `db/migrations/20260923000001_doctornect_schema.sql` (FKs without dedicated indexes — per migration audit)
- Problem: RLS/RPC EXISTS subqueries may seq-scan.
- Impact: Slow lists at scale.
- Fix: New migration adding indexes on both columns.
- Effort: S
- Type: Needs manual action (migration)
- Status: **PARTIAL** — `db/migrations/20261103000012_patient_doctor_fk_indexes.sql` added; apply on staging/RDS

#### [DB-002] `enqueue_notification_outbox` SECURITY DEFINER `search_path = public`
- Severity: Medium
- Module(s): All
- Location: `db/migrations/20261103000010_notification_outbox.sql` (~37–41)
- Problem: Mutable search_path on SECURITY DEFINER function.
- Impact: Search-path injection if attacker can create objects in `public`.
- Fix: New migration `SET search_path = ''` + fully qualified names.
- Effort: S
- Type: Needs manual action

#### [DB-003] `patients_update` uses `USING (true)`
- Severity: Medium
- Module(s): Patient
- Location: `db/migrations/20261102000001_round6_guards_and_kyc.sql` (~282–285)
- Problem: UPDATE allowed for any authenticated row at USING stage; relies on WITH CHECK.
- Impact: Broader attack surface if WITH CHECK bypass found.
- Fix: Tighten USING to owner/admin predicate.
- Effort: M
- Type: Needs manual action

#### [CFG-001] `secure_config.js` comment contradicts code
- Severity: Low
- Module(s): All
- Location: `backend/functions/secure_config.js:6–10` vs `index.js:458` (`defineSecret` via params)
- Problem: Comment says Secret Manager bindings removed; `index.js` still uses `defineSecret('SUPABASE_SERVICE_ROLE_KEY')` etc.
- Impact: Operator confusion; wrong deploy procedure.
- Fix: Update comment or restore consistent secret strategy per `SECRETS_MIGRATION_PLAN.md`.
- Effort: S
- Type: Auto-fixable by Cursor
- Status: **FIXED** — comment aligned with `index.js` `defineSecret` bindings

#### [CFG-002] Default `APP_ENV=staging` in client db client
- Severity: Medium
- Module(s): All
- Location: `backend/functions/src/db/client.js:18–19`
- Problem: Missing `APP_ENV=production` on prod functions → staging Supabase URL/key.
- Impact: Prod functions writing to staging DB (catastrophic if mis-set).
- Fix: Enforce production env in deploy pipeline; add startup assert on project id hash.
- Effort: M
- Type: Needs manual action

#### [CFG-003] `.env.example` sets `FIRESTORE_FORBIDDEN=0`
- Severity: Info
- Module(s): All
- Location: `backend/functions/.env.example:64`
- Problem: Backend allows Firestore while client defaults forbid.
- Impact: Inconsistent mental model for operators.
- Fix: Document in ENVIRONMENTS.md; align prod to `1` when Firestore retired server-side.
- Effort: S
- Type: Auto-fixable by Cursor (docs/example comment)
- Status: **FIXED** — clarified client vs server default in `backend/functions/.env.example` (value stays `0` per `env_parity.test.js`)

#### [S3-001] S3 upload validation — verify size/type whitelist in production path
- Severity: Medium
- Module(s): Doctor, Patient, Lab, Pharmacy
- Location: `backend/functions/s3_storage.js` (UNVERIFIED line-by-line in this pass)
- Problem: Medical uploads must enforce content-type and max size server-side.
- Impact: Malware/large object cost.
- Fix: Audit `getS3UploadUrl` handler; add explicit limits if missing.
- How to verify: `npm test -- test/s3_storage.test.js`
- Effort: M
- Type: Auto-fixable by Cursor
- Status: UNVERIFIED (partial — tests exist)

#### [APP-001] Thirteen known failing Flutter tests
- Severity: Medium
- Module(s): Doctor, Patient, Lab
- Location: `docs/audit/baseline_flutter_failing_tests.txt`
- Problem: Auth resilience + Firestore ordering tests fail (legacy architecture).
- Impact: Regressions not caught locally; release confidence reduced.
- Fix: Update tests for Supabase-primary or fix implementations.
- Effort: L
- Type: Auto-fixable by Cursor

#### [APP-002] `profile_draft_store` always reads/clears Firestore
- Severity: Medium
- Module(s): All
- Location: `frontend/lib/core/auth/profile_draft_store.dart:81–84, 114–117`
- Problem: Ignores cutover for get/clear.
- Impact: Onboarding draft errors when Firestore forbidden.
- Fix: Supabase draft table or local secure storage only.
- Effort: M
- Type: Auto-fixable by Cursor

#### [OPS-001] Flutter CI runs full suite including 13 failures
- Severity: Low
- Module(s): All
- Location: `.github/workflows/flutter-ci.yml:37–38`
- Problem: `flutter test` on PR to main will fail if branch merged as-is.
- Impact: CI red on main.
- Fix: Fix tests or split baseline allowlist job.
- Effort: M
- Type: Auto-fixable by Cursor

#### [OPS-002] No backend functions CI in root workflows grep
- Severity: Medium
- Module(s): All
- Location: `.github/workflows/` — only `flutter-ci.yml`, `gateway_ci.yml`, `build-apk.yml`
- Problem: Backend regressions rely on manual `npm test`.
- Impact: SEC-001-class bugs reach deploy.
- Fix: Add `backend/functions` npm test workflow on PR.
- Effort: S
- Type: Auto-fixable by Cursor
- Status: **FIXED** — `.github/workflows/backend-functions-ci.yml` runs `npm test` + audit on PR

#### [G1-001] Post-OTP `exists`/`role` fleet gap
- Severity: High
- Module(s): All
- Location: `docs/audit/APP_BACKEND_CONTRACT.md` G1
- Problem: Deployed Oct 24 backend may lack fields client expects.
- Impact: Wrong login/register routing without fallback.
- Fix: Login hotfix deploy or rely on legacy lookup (documented).
- Effort: M
- Type: Needs manual action

#### [ADM-001] Super-admin verification service touches all role collections (cross-exposure)
- Severity: Medium
- Module(s): All (Admin app separate)
- Location: `frontend/lib/core/admin/super_admin_verification_service.dart` (~87–305)
- Problem: Shared client binary may include admin Firestore paths; affects store build surface.
- Impact: Admin logic in patient app binary; Firestore reads if invoked.
- Fix: Move to admin flavor/module or compile-time exclude from role apps.
- Effort: L
- Type: Needs manual action

*(Additional Info items: Firestore rules deny-all `backend/firestore.rules:7–8`; Storage deny-all `backend/storage.rules:6–8`; OTP expiry 10m `registration_otp.js:23`; Redis env slug `redis_keys.js:7–16`; npm audit 0 vulns — verified this session.)*

---

## 4. Missing / Wrong `.env` Variables

Template reference: `backend/functions/.env.example` (no live `.env` read in this audit).

| Variable | Used in (file:line) | In .env.example? | Staging needed | Production needed | Notes |
|----------|---------------------|------------------|----------------|-------------------|-------|
| `PROD_GATEWAY_URL` | `src/db/client.js:22` | Yes | No | **Yes** | Production Postgres gateway |
| `PROD_GATEWAY_SERVICE_KEY` | `src/db/client.js:26` | Yes | No | **Yes** | UNVERIFIED RDS live |
| `STAGING_SUPABASE_URL` | `src/db/client.js:23` | Yes | **Yes** | No | |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY` | `src/db/client.js:27` | Yes | **Yes** | No | Use SM binding in prod deploy |
| `OTP_REDIS_MIRROR` | `index.js:126`, `registration_otp.js:87` | Yes | Optional | Optional | Drives secret bind set |
| `REDIS_HOST/PORT/PASSWORD` | `src/config/redis.js`, `registration_otp.js` | Yes | If mirror on | If mirror on | **Check 0 overlap** if plain in deploy `.env` |
| `MSG91_AUTH_KEY` | `secure_config.js:25–28` | Yes | Yes | Yes | SM in prod |
| `ENFORCE_OTP_APP_CHECK` | `index.js:141–143` | Yes | Dev false ok | **Must true** | Example shows false for dev |
| `ENABLE_REVIEW_DEMO` | `registration_otp.js:132` | Yes | No | Only review window | |
| `SUPABASE_SECRET_KEY` | `secure_config.js:48` | No (uses `SUPABASE_SERVICE_ROLE_KEY` line) | Alias | Alias | Example lists `SUPABASE_SERVICE_ROLE_KEY`; code accepts `SUPABASE_SECRET_KEY` alias |
| `GOOGLE_PLAY_REVIEW_PHONE` | `production_otp_guard.js:8` | **No** | Optional | Must be unset | Blocked in prod guard if set |
| `DATABASE_URL` | UNVERIFIED direct use | Yes | Migrations | RDS | Used by scripts not functions runtime |

---

## 5. Prioritized Fix Roadmap

### Must fix before publish/launch
1. ~~**SEC-001**~~ — **FIXED** in repo
2. **SEC-003** — Check 0 / Redis overlap
3. **SEC-004** — Deploy `cleanupPendingRegistration`
4. **SEC-002** — apply migration `20261103000011` on staging/RDS
5. **ARCH-001** — Ambulance Firestore excision (doctor profile persist fixed for cutover)
6. ~~**AUTH-001**~~ — **FIXED** in repo (caller identity); full booking still Firestore-backed
7. **G1-001** — Login hotfix decision (G1)
8. **CFG-002** — Production `APP_ENV` verification on all functions

### Fix within first week
- **DB-001**, **DB-002**, **DB-003**, **ARCH-003**, **APP-002**, **OPS-002**, **S3-001** verification

### Backlog
- **APP-001** test debt, **ADM-001** admin split, **OPS-001** CI policy, **CFG-003** docs

---

## 6. Manual Steps for the Owner

1. **Secret Manager:** Create/verify secrets `SUPABASE_SERVICE_ROLE_KEY`, `REDIS_*`, `MSG91_AUTH_KEY`, AWS keys; remove plain duplicates from deploy `.env`.
2. **Firebase deploy:** `firebase deploy --only functions:cleanupPendingRegistration` after Gate 2 (`docs/audit/RELEASE_GATE.md`).
3. **Supabase/RDS:** Apply new RLS/index migrations on staging; replay on fresh RDS; run `scripts/test_live_rls_idor.js` (staging credentials — not in agent session).
4. **AWS:** Confirm S3 bucket public access block, SSE, separate staging/prod buckets/prefixes, lifecycle rules — **UNVERIFIED** (console).
5. **RDS:** Provision SSL, backups, PITR, security groups — **UNVERIFIED** (`docs/runbooks/RDS_MIGRATION_RUNBOOK.md`).
6. **MSG91 / Play Console:** Rotate keys if `.env.bak` exposure applied (`docs/audit/ENV_BAK_EXPOSURE.md`); configure reviewer credentials per `REVIEW_*` policy.
7. **Pre-push:** Run `docs/audit/PRE_PUSH_HISTORY_CHECK.md` gate before pushing branch.

---

## 7. What Is Already Good

- Firestore **client rules deny-all** (`backend/firestore.rules:7–8`).
- Firebase **Storage rules deny-all** (`backend/storage.rules:6–8`).
- **No Firestore document triggers** exported from current `backend/functions/index.js` (~1285 comment).
- **`isDoctorPatientSupabasePrimary()`** forced true in production code path (`sync_flags.js:47–51`).
- **OTP production guard** blocks `OTP_TEST_MODE` and demo phone env on prod project cold start (`production_otp_guard.js:98–116`).
- **Layered OTP rate limits** (`registration_otp.js` + `abuse_rate_limit.js`).
- **App Check** enforcement flags on sensitive callables (`index.js:141–150`, `assertAppCheck`).
- **Flutter analyze: 0 issues** (this session).
- **Backend unit tests: 494 pass, 0 fail** (this session).
- **`npm audit`: 0 vulnerabilities** in `backend/functions` (this session).
- **Redis key env slug** (`redis_keys.js:7–16`).
- **IDOR/RLS test harness** exists (`scripts/test_live_rls_idor.js`, multiple `backend/functions/test/*rules*.test.js`).

---

## 8. Not Verified

| Item | Needed to verify |
|------|------------------|
| AWS RDS production live wiring | `PROD_GATEWAY_*` pointed at real RDS; connection SSL |
| S3 bucket IAM / public access | AWS console or read-only IAM audit |
| Git history secret leakage | Owner pickaxe scans (`PRE_PUSH_HISTORY_CHECK.md`) |
| MSG91 / Razorpay / AWS keys in old deploy artifacts | Redeploy + rotation per `ENV_BAK_EXPOSURE.md` |
| Live Cloud Functions env vs branch (`defineSecret` vs plain) | `gcloud functions describe` metadata names only |
| Supabase Security Advisor full export | Dashboard run on staging project |
| Play Store reviewer end-to-end on production build | Manual device test |
| Load testing 1k/10k users | k6 or staging soak |
| HIPAA / DPDP legal compliance | Legal/compliance review (posture notes only in this audit) |
| Admin separate app impact on shared backend | Admin team integration test |

---

## Phase 2 — Fix status

*(Updated after auto-fixes in this session.)*

| ID | Status |
|----|--------|
| SEC-001 | **FIXED** — removed dead `isDemoPhone` login branch |
| AUTH-001 | **FIXED** — `resolveCallerIdentity` in `bookAppointmentHandler` |
| ARCH-002 | **FIXED** — Supabase persist when cutover enabled |
| SEC-002 | **PARTIAL** — migration file added; owner applies SQL |
| DB-001 | **PARTIAL** — index migration added; owner applies SQL |
| CFG-001 | **FIXED** — `secure_config.js` header comment |
| CFG-003 | **FIXED** — `.env.example` comment |
| OPS-002 | **FIXED** — backend-functions CI workflow |
| SEC-003, SEC-004, ARCH-001, G1-001, CFG-002 | **OPEN – manual action needed** |

**Rating before fixes:** 5.5 / 10  
**Rating after Phase 2 auto-fixes:** **6.5 / 10** (login + patient booking auth + doctor persist path; deploy/RLS/ambulance blockers remain)
