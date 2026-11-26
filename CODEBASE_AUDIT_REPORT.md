 # DoctorNect (Medibond) — Complete 9-Type Codebase Audit Report

| Field | Value |
|-------|-------|
| **Report file** | `CODEBASE_AUDIT_REPORT.md` |
| **Audit date** | 2026-11-25 |
| **Last verified pass** | 2026-11-25 (continuation — source re-validation; no slow line-count job) |
| **Scope** | Entire repository (read-only static analysis) |
| **Auditor roles** | Software Architecture, Security, DevOps, QA, Performance, Privacy, UI/UX |
| **Code changes** | None (report file only) |
| **Overall risk level** | **HIGH** (production-facing security and wiring gaps; strong foundation) |

---

## 1. Executive Summary

DoctorNect is a multi-role healthcare platform (patient, doctor, lab, pharmacy, ambulance, admin) built as a Flutter client over Firebase Auth/Cloud Functions, an AWS Auth Gateway + PostgREST edge, and PostgreSQL (RDS production / Supabase staging) with S3 for clinical files.

**Overall application health:** Architecturally mature for a cutover-era product — deny-all Firestore/Storage, JWT-minting gateway with table/RPC allowlists, extensive RLS migrations, and a large automated test corpus. **Overall risk is HIGH** because several **confirmed** object-level authorization bugs in S3 confirm flows can corrupt PHI pointers, S3 Cloud Function callables appear **not exported** from the deploy entrypoint while the Flutter client still calls them, and production gateway revocation/Docker dependency assumptions are weak.

### Key concerns
1. Lab-report and health-record `confirmS3Upload` updates lack ownership filters (IDOR / integrity).
2. S3 callables defined in `s3_storage.js` are not re-exported from `backend/functions/index.js`.
3. Hardcoded default PostgREST JWT secret in gateway config (fail-open if env missing).
4. ECS sets `NODE_ENV=production` but not `APP_ENV=production`; revocation is not fail-closed.
5. Privacy copy still describes Firebase Storage for reports while runtime uses AWS S3; processors (Razorpay/MSG91/AWS) under-named.
6. Accessibility Semantics almost absent; mega-files hinder maintainability.

### Major strengths
- Deny-all Firestore and Firebase Storage rules; PHI intended for Postgres + S3.
- Auth gateway: Firebase JWKS verify, short-lived minted JWTs (60s), allowlists, CORS exact origins, timing-safe service key compare.
- Strong RLS patterns (`auth.jwt()->>'sub'`, column locks, KYC immutability, super-admin hardening).
- Secrets hygiene: `.env` / `google-services.json` / service accounts gitignored; no live keys found in tracked source.
- Large test inventory (Flutter ~95, Functions ~92, gateway 5, scripts 28) and env-policy CI.
- Terraform: ALB TLS 1.3, WAF, ECS dual-container, Secrets Manager, security groups.

### Top 5 urgent findings

| ID | Title | Severity |
|----|-------|----------|
| SEC-01 | Lab report confirm IDOR (any lab → any booking) | **HIGH** |
| SEC-02 | Health-record confirm `recordId` integrity IDOR | **HIGH** |
| CQ-01 / SEC-10 | S3 callables not exported from Functions `index.js` | **HIGH** |
| SEC-03 | Default PostgREST JWT secret fallback in gateway | **HIGH** |
| DEVOPS-01 | Gateway Docker image omits `npm install` / `firebase-admin` while revocation depends on it | **HIGH** |

### Recommended immediate actions
1. Patch `confirmS3Upload` ownership for `lab_reports` and `health_records`.
2. Re-export (or intentionally retire) S3 callables from `index.js` and verify deploy.
3. Fail closed on missing/default `PGRST_JWT_SECRET`; set `APP_ENV=production` on ECS; fix gateway image build.
4. Enable ambulance HTTP App Check in production; tighten CSP `connect-src`.
5. Do **not** treat this report as a legal compliance sign-off or live pentest.

---

## 2. Project Overview

### Technology stack

| Layer | Technology |
|-------|------------|
| Client | Flutter (`frontend/`, package name `medibond`, Dart ≥3.2) — Android/iOS/Web (+ desktop folders) |
| Auth | Firebase Authentication (OTP/custom claims), App Check (partial) |
| Backend compute | Firebase Cloud Functions v2, Node 22 (`backend/functions`) |
| Data API edge | Node Auth Gateway (`services/api-gateway`) → PostgREST |
| Database | PostgreSQL 18 (AWS RDS prod; Supabase staging/demo plane) |
| Object storage | AWS S3 (presigned URLs) |
| Cache / abuse | Redis (OTP mirror, banner/S3 URL cache, optional) |
| Payments | Razorpay (orders, verify, webhook) |
| Messaging | FCM; MSG91 OTP/email |
| Infra | Terraform AWS (`infra/aws`): ALB, WAF, ECS Fargate, Secrets Manager, CloudWatch |
| Hosting | Firebase Hosting for Flutter web (`frontend/build/web`) |

### Architecture (summary)

```text
Flutter App
  ├─ Firebase Auth / Cloud Functions (OTP, admin, Razorpay, appointments, S3 intended)
  └─ Supabase client (Firebase ID token) ──► ALB+WAF ──► Auth Gateway ──► PostgREST ──► RDS
                                                                    └─ demo PostgREST (optional)
Cloud Functions ──► Postgres (service role / pool), S3, Redis, MSG91, Razorpay, FCM
```

### Project structure overview

| Path | Role |
|------|------|
| `frontend/` | Flutter application |
| `backend/functions/` | Cloud Functions |
| `backend/firestore.rules`, `storage.rules` | Deny-all client rules |
| `services/api-gateway/` | PostgREST auth gateway |
| `db/migrations/` | 71 shared SQL migrations + RDS bootstrap/overrides |
| `infra/aws/` | Terraform |
| `scripts/` | Migrate, RLS harness, env guards, smoke |
| `docs/` | Runbooks, checklists, prior audits |
| `.github/workflows/` | CI (check-only; no Terraform/Firebase deploy) |

### Integrations
Firebase (Auth, Functions, FCM, Remote Config, App Check, Hosting), AWS (RDS, S3, ECS, ALB, WAF, Secrets Manager), Supabase (staging/demo), Razorpay, MSG91, Google Maps Geocoding (optional), Redis.

---

## 3. Audit Methodology

### What was inspected
- Repository structure, manifests, lockfiles, Firebase/Terraform/CI configs.
- Auth gateway source (`server.js`, `config.js`, token/JWT/CORS/security modules).
- Cloud Functions entry (`index.js`), OTP, S3, Razorpay, admin, delete-account, HTTP security.
- Firestore/Storage rules; sample RLS migrations and bootstrap roles.
- Flutter `lib/` structure, auth, legal content, S3 client, accessibility greps.
- Test inventories and CI workflow definitions.
- `.gitignore` / tracked secret-like paths via `git ls-files`.
- Prior open-issue notes in `docs/OPEN_ISSUES.md` (re-validated selectively).

### Tools used
- Static file reads / ripgrep / PowerShell & Python inventory scripts.
- Parallel read-only exploration agents for architecture, security, deps/tests/devops, quality/perf/privacy/UX.
- **No** `npm audit` / OSV / dependency CVE database queries in this run.
- **No** live exploit, load test, browser screenshot, or production environment access.
- **No** package installs; **no** source modifications except this report.

### Tests executed
**None in this audit run.** Historical Flutter artifacts (`frontend/test_results*.json`) exist but are **not** treated as this-run results.

### Continuation pass (same date)
- Re-read `CODEBASE_AUDIT_REPORT.md` against source; all nine audit sections were present but several findings used approximate line numbers or thin test-gap analysis.
- **Re-validated in source:** `s3_storage.js` (confirm IDOR), `index.js` vs `s3_storage.js` exports, `s3_presign_api.dart` callables, gateway `config.js` / `server.js` / `security.js` / `token_verifier.js`, `firebase_revocation.js`, ECS task env (`ecs.tf`), `http_endpoint_security.js`, ambulance HTTP XFF (`index.js`), `demo_routing.js`, CI workflows, `ENVIRONMENTS.md`, legal copy, invite URLs, repository `.limit()` caps, `s3_storage.test.js` coverage gaps.
- **Added:** SEC-13 (gateway response headers), TEST-07 (confirm-path regression gap).
- **Did not re-run:** large-file inventory, PowerShell recursive line-count, `npm audit`, live test execution, production deploy inventory.

### Scope & limitations
- Read-only static analysis of the local checkout.
- Runtime deploy state (which Functions are live, actual Secrets Manager values, RDS backup settings) **not verified**.
- CVE verification **not performed**.
- Visual UI audit is **source-code only** (no running app screenshots).
- Legal conclusions are **not** made; privacy notes are technical gap observations only.

---

## 4. Overall Audit Scorecard

| Audit | Status | Risk | Findings (approx.) | Audit Coverage | Summary |
|-------|--------|------|--------------------|----------------|---------|
| 1. Security & Vulnerability | Complete (re-validated) | **High** | 13 | High | Strong gateway/RLS/secrets; confirmed S3 IDOR + JWT default + App Check gaps |
| 2. Dependency & Supply Chain | Complete (re-validated) | Medium | 8 | Medium | Lockfiles on main runtimes; gateway Docker omits install; CVE not re-run |
| 3. Code Quality & Maintainability | Complete (re-validated) | Medium | 6 | High | Mega-modules/screens; S3 export wiring; low TODO debt |
| 4. Architecture & Scalability | Complete (re-validated) | Medium | 6 | High | Solid edge design; in-memory rate limits; dual-plane isolation |
| 5. Performance & Resources | Complete (re-validated) | Medium | 5 | Medium | Static only; large assets; pagination caps |
| 6. Testing & Reliability | Complete (re-validated) | Medium | 7 | High | Large suites; confirm IDOR gap in tests; scripts/RLS not in CI |
| 7. Compliance, Privacy & License | Complete (re-validated) | Medium | 6 | Medium | deleteMyAccount + legal docs; processor disclosure/LICENSE gaps |
| 8. UI/UX & Accessibility | Complete (re-validated) | Medium | 7 | Medium | Source-only; near-zero Semantics |
| 9. DevOps, CI/CD & Infrastructure | Complete (re-validated) | **High** | 9 | High | Solid Terraform; check-only CI; alarms without SNS; Docker/APP_ENV gaps |

**Scoring note:** No numeric 0–100 scores are assigned. Risk is qualitative from severity × confidence of verified findings.

---

## 5. Detailed Audit Reports

### AUDIT 1: Security & Vulnerability

**Objective:** Identify authentication, authorization, API, secrets, upload, and config risks with evidence.  
**Scope:** Gateway, Functions, rules, Flutter auth client paths, infra secrets wiring, hosting headers.  
**Status:** Complete (static).

#### Findings

##### SEC-01 — Lab report confirm IDOR
| Field | Detail |
|-------|--------|
| Severity | **HIGH** |
| Confidence | **CONFIRMED** |
| Status | Open |
| File | `backend/functions/s3_storage.js` |
| Lines | 1330–1333, 1423–1436 |
| Evidence | Role check is `caller.role !== 'lab'` only; DB update uses `.eq('booking_id', recordId)` with **no** `lab_id` / ownership filter on service client. |
| Impact | Lab A can attach/overwrite report pointers on Lab B’s booking → wrong PHI for patients; integrity failure. |
| Business impact | Misdiagnosis risk, trust/regulatory exposure, support incidents. |
| Reproduction | Authenticated lab user calls `confirmS3Upload` with another booking’s `recordId` and an object under an allowed prefix (safe to validate in staging only). |
| Remediation | Load booking; assert `booking.lab_id === caller.profileId`; update with both keys. |
| Effort | Small |
| Immediate | **Yes** |

##### SEC-02 — Health-record confirm recordId integrity IDOR
| Field | Detail |
|-------|--------|
| Severity | **HIGH** |
| Confidence | **CONFIRMED** |
| Status | Open |
| File | `backend/functions/s3_storage.js` |
| Lines | 1325–1328, 1409–1422 |
| Evidence | Object-key prefix ownership checked, but update is `.eq('record_id', recordId)` only — no `patient_id` match. |
| Impact | Patient A can repoint Patient B’s `health_records` row to A’s object. |
| Remediation | `.eq('record_id', recordId).eq('patient_id', caller.profileId)` and reject mismatch. |
| Effort | Small |
| Immediate | **Yes** |

##### SEC-03 — Hardcoded default PostgREST JWT secret
| Field | Detail |
|-------|--------|
| Severity | **HIGH** |
| Confidence | **HIGH** |
| Status | Open (mitigated if Secrets Manager always set) |
| File | `services/api-gateway/src/config.js` |
| Lines | 21 |
| Evidence | `postgrestJwtSecret: process.env.PGRST_JWT_SECRET \|\| 'doctornect-secure-postgrest-jwt-secret-min32chars'` |
| Impact | Misconfigured deploy can allow offline minting of PostgREST JWTs including `service_role` if that role is accepted with the same secret. ECS Terraform **does** inject the secret (`infra/aws/ecs.tf` ~85–116). |
| Remediation | Fail closed in production if unset or equal to default; rotate any environment that ever used the default. |
| Effort | Small |
| Immediate | **Yes** |

##### SEC-04 — Production revocation not fail-closed (`APP_ENV` unset in ECS)
| Field | Detail |
|-------|--------|
| Severity | **MEDIUM** |
| Confidence | **HIGH** |
| Status | Open |
| Files | `services/api-gateway/src/config.js:16`, `firebase_revocation.js:36–43`, `services/api-gateway/src/server.js:315–316`, `infra/aws/ecs.tf:78–83` |
| Evidence | `requireFirebaseRevocationCheck` only when `APP_ENV === 'production'` (`config.js:16`). `assertFirebaseTokenNotRevoked` passes `required: cfg.requireFirebaseRevocationCheck === true` (`server.js:315–316`). ECS task env sets `NODE_ENV=production` but **not** `APP_ENV`. Without Admin SDK, revocation is skipped (`firebase_revocation.js:39–43`). |
| Impact | Revoked sessions may still pass JWKS-only verify. |
| Remediation | Set `APP_ENV=production`; treat missing Admin as hard failure in prod. |
| Effort | Small |

##### SEC-05 — Ambulance HTTP App Check off by default
| Field | Detail |
|-------|--------|
| Severity | **MEDIUM** |
| Confidence | **CONFIRMED** |
| Files | `backend/functions/http_endpoint_security.js:62–65`, `backend/functions/index.js:1015–1045` |
| Evidence | `isAmbulanceHttpAppCheckEnforced()` returns true only when `ENFORCE_AMBULANCE_HTTP_APP_CHECK === 'true'` (default `'false'` at line 63). `verifyAmbulanceDriverLoginHttp` documents default-off App Check at lines 1015–1017 and calls `assertAmbulanceHttpAppCheck` at line 1045. |
| Impact | Credential stuffing / PIN guessing against public HTTP (rate limits help). |
| Remediation | Enforce App Check in production. |
| Effort | Small |

##### SEC-06 — Firebase claim → `app_role` fallback ambiguity
| Field | Detail |
|-------|--------|
| Severity | **MEDIUM** |
| Confidence | **HIGH** |
| File | `services/api-gateway/src/token_verifier.js` |
| Lines | 104–106 |
| Evidence | `appRole: payload.app_role \|\| payload.user_role \|\| payload.role \|\| 'patient'` while Firebase custom claims also set `role: 'authenticated'`. |
| Impact | Unexpected PostgREST `app_role` when claims incomplete (usually fail-closed via RLS, not admin escalate). |
| Remediation | Allowlist only `app_role`/`user_role`; never map Firebase `role`. |
| Effort | Small |

##### SEC-07 — Hosting CSP `connect-src` overly broad
| Field | Detail |
|-------|--------|
| Severity | **MEDIUM** |
| Confidence | **CONFIRMED** |
| File | `firebase.json` (~169–170) |
| Evidence | `connect-src 'self' https: wss:;` |
| Impact | XSS can exfiltrate tokens/PHI to any HTTPS endpoint. |
| Remediation | Pin Firebase, gateway, Razorpay, Maps, etc. |
| Effort | Medium |

##### SEC-08 — In-memory gateway rate limits
| Field | Detail |
|-------|--------|
| Severity | **LOW** |
| Confidence | **CONFIRMED** |
| Files | `services/api-gateway/src/security.js` (~27–56), `server.js` (~71–88) |
| Impact | Limits dilute across ECS tasks. |
| Remediation | Redis/shared limiter or rely on WAF rate rules. |
| Effort | Medium |

##### SEC-09 — Upload MIME trust without magic-byte sniff
| Field | Detail |
|-------|--------|
| Severity | **LOW** |
| Confidence | **CONFIRMED** |
| File | `backend/functions/s3_storage.js` (allowlist + HEAD metadata) |
| Impact | Polyglot payloads if Content-Type matches signed type. |
| Remediation | Sniff on confirm; optional malware scan. |
| Effort | Medium |

##### SEC-10 — S3 callables not wired through Functions entrypoint
| Field | Detail |
|-------|--------|
| Severity | **HIGH** |
| Confidence | **CONFIRMED** (code wiring); deploy state **NEEDS VALIDATION** |
| Files | `backend/functions/s3_storage.js:1533–1565`, `backend/functions/index.js:115–118`, `frontend/lib/core/storage/s3_presign_api.dart:93–161,226` |
| Evidence | `s3_storage.js` exports onCall handlers (`getS3UploadUrl`, `confirmS3Upload`, etc.). `index.js` only destructures `awsAccessKeyId`/`awsSecretAccessKey` from `./s3_storage` — no `exports.getS3*`. Flutter calls `httpsCallable('getS3UploadUrl')`, `getS3DownloadUrl`, `getS3DownloadUrls`, `confirmS3Upload` at lines 93, 129, 161, 226. |
| Impact | Client calls may fail in correctly deployed environments; or stale undeployed exports may diverge from source. Blocks/breaks KYC and clinical uploads. |
| Remediation | Re-export callables from `index.js` (or remove client usage); verify live function list. |
| Effort | Small–Medium |
| Immediate | **Yes** |

##### SEC-11 — Ambulance HTTP trusts leftmost `X-Forwarded-For`
| Field | Detail |
|-------|--------|
| Severity | **LOW** |
| Confidence | **CONFIRMED** |
| File | `backend/functions/index.js:1039–1041` (contrast `services/api-gateway/src/server.js:105–109`) |
| Evidence | Ambulance HTTP uses `String(req.headers['x-forwarded-for']||...).split(',')[0]` (leftmost hop). Gateway uses **rightmost** hop in XFF chain. |
| Impact | Rate-limit key spoofing if proxy does not overwrite XFF. |
| Remediation | Align on trusted hop / platform IP. |
| Effort | Small |

##### SEC-12 — Demo UID prefix routing config risk
| Field | Detail |
|-------|--------|
| Severity | **LOW** |
| Confidence | **HIGH** |
| File | `scripts/lib/demo_routing.js` |
| Lines | 65–68 |
| Evidence | When `DEMO_UID_PREFIX_ROUTING=1`, UIDs starting `demo_` or `demo_user_` resolve to demo plane (`isDemoFirebaseUid`). |
| Impact | If `DEMO_UID_PREFIX_ROUTING=1`, prefix-based plane routing may mis-route. Client hints are rejected (strength). |
| Remediation | Prefer explicit UID allowlist; keep prefix routing off in prod. |
| Effort | Small |

##### SEC-13 — Gateway API responses omit browser security headers
| Field | Detail |
|-------|--------|
| Severity | **LOW** |
| Confidence | **CONFIRMED** |
| Status | Open |
| File | `services/api-gateway/src/server.js` |
| Lines | 121–133 |
| Evidence | `sendJson` sets only `Content-Type`, CORS-related headers, and optional `Access-Control-Allow-Origin`. No `X-Content-Type-Options`, `X-Frame-Options`, `Strict-Transport-Security`, or `Content-Security-Policy` (Firebase Hosting sets these for web static assets in `firebase.json`, not for direct API clients). |
| Impact | Lower risk for non-browser API consumers; browsers calling the gateway directly get weaker baseline hardening than hosted web. |
| Remediation | Add minimal security headers on gateway (and/or at ALB); document that API is not intended as an HTML surface. |
| Effort | Small |
| Immediate | No |

#### Security strengths
- Deny-all Firestore (`backend/firestore.rules`) and Storage (`backend/storage.rules`).
- Gateway allowlists, schema lock to `public`, 60s minted JWT, timing-safe service key, failed-key throttle.
- Hosting security headers (HSTS, CSP, COOP, nosniff, frame deny).
- No tracked `google-services.json` / service-account / live API keys found via `git ls-files`.
- Razorpay webhook verifies `x-razorpay-signature` with `crypto.timingSafeEqual` (`backend/functions/promoted_ads.js:636`).
- Lab **upload** URL path enforces booking ownership (`s3_storage.test.js:382–408` rejects lab_1 uploading for lab_2 booking) — gap is **confirm** path only (SEC-01/02).
- `approveUserAccount` requires configured admin email allowlist + `email_verified` (`registration_otp.js:653–673`) — older OPEN_ISSUES “auto-approval on OTP” claim **not reproduced** in `completeMobileOtpLogin` (sets claims/custom token only).

#### Limitations
Live IDOR exploitation, WAF efficacy, and production secret values were not tested.

---

### AUDIT 2: Dependency & Supply Chain

**Objective:** Assess manifests, lockfiles, version hygiene, and supply-chain risks.  
**Status:** Complete (CVE DB **not** queried).

#### Key versions (declared / locked samples)
| Package | Area | Notes |
|---------|------|-------|
| `firebase-admin` | Functions ^14.4.0 / Gateway ^14.4.0 | Gateway Docker may not install it |
| `@supabase/supabase-js` | Functions ^2.117.0 | Locked ~2.118 |
| `@aws-sdk/client-s3` | Functions ^3.1141.0 | |
| `razorpay_flutter` | Flutter ^1.3.7 | Locked ~1.4.6 |
| `timezone` | Flutter **`any`** | Locked 0.10.1 |

#### Findings
| ID | Severity | Confidence | Finding | Evidence | Remediation |
|----|----------|------------|---------|----------|-------------|
| DEP-01 | Medium | High | Unbounded `timezone: any` | `frontend/pubspec.yaml:47` | Pin constraint |
| DEP-02 | Medium | High | Missing lockfiles (root, `scripts/`, `gcp-msg91-proxy`) | manifests | Add locks; `npm ci` |
| DEP-03 | **High** | High | Gateway Dockerfile copies `package.json` but does **not** install deps | `services/api-gateway/Dockerfile:10–12` comment “zero external npm dependencies” | `npm ci --omit=dev` if Admin revocation required |
| DEP-04 | Medium | High | `firebase-admin` major skew (scripts 12.x vs functions 14.x) | lockfiles | Align majors |
| DEP-05 | Low | Med | Gateway CI runs tests/audit without `npm ci` | `.github/workflows/gateway_ci.yml:29–37` (`node --test` then `npm audit` only) | Always `npm ci` before test + audit |
| DEP-06 | Low | Med | Functions CI Node 20 vs engines 22 | `.github/workflows/backend-functions-ci.yml:27` vs `backend/functions/package.json:5` (`"node": "22"`) | Align CI to Node 22 |
| DEP-07 | Info | High | CVE verification not performed this run | — | Run `npm audit` / OSV / pub advisory periodically |
| DEP-08 | Low | Med | MSG91 proxy Docker `npm install` without lock | Dockerfile | Lock + `npm ci` |

#### Strengths
Functions `overrides` for transitive packages; Flutter + functions + gateway lockfiles present; no postinstall hooks found in scanned package.json files.

---

### AUDIT 3: Code Quality & Maintainability

**Objective:** Maintainability risks grounded in size, wiring, and duplication — not style preference.  
**Status:** Complete.

#### Large files (application source, excl. `node_modules` / tests)
| Lines | Path |
|------:|------|
| 4610 | `backend/functions/cross_role_sync.js` |
| 3501 | `backend/functions/registration_otp.js` |
| 2656 | `frontend/lib/features/ambulance/ambulance_booking_screen.dart` |
| 2465 | `frontend/lib/features/promoted_ads/screens/create_promoted_ad_screen.dart` |
| 2336 | `frontend/lib/features/shared/screens/patient_profile_screen.dart` |
| 1610 | `backend/functions/s3_storage.js` |

#### Findings
| ID | Severity | Confidence | Finding | Evidence | Remediation |
|----|----------|------------|---------|----------|-------------|
| CQ-01 | **High** | Confirmed | S3 callables not exported from deploy entry | See SEC-10 | Wire exports |
| CQ-02 | Medium | High | God-modules / mega-screens | LOC table | Split by domain |
| CQ-03 | Medium | High | Hardcoded invite/marketing URLs | `doctor_invite_service.dart:17`, `ambulance_invite_service.dart:17`, `pharmacy_doctor_invite_service.dart:8` (`https://doctornect.com/...`) | dart-define / Remote Config |
| CQ-04 | Medium | Med | Duplicated delete-account error UX across roles | profile screens | Shared controller |
| CQ-05 | Low | High | Zero TODO/FIXME in scoped trees | grep | Keep hygiene |
| CQ-06 | Low | Med | Medibond vs DoctorNect naming mix | pubspec / legal / Firebase project | Document aliases |

#### Strengths
Feature-first Flutter layout; gateway modular `src/`; client-facing error sanitization helpers.

---

### AUDIT 4: Architecture & Scalability

**Objective:** Evaluate architecture fitness and scale limits with evidence.  
**Status:** Complete.

#### Current architecture
Flutter multi-role client → Firebase Auth/Functions + Auth Gateway/PostgREST → PostgreSQL; S3 for objects; Redis optional; demo/real dual plane resolved **server-side**.

#### Strengths
- Clear separation: deny-all Firestore vs Postgres primary.
- Gateway allowlists + short-lived JWT + RLS defense-in-depth.
- Extensive indexes in base schema (appointments, prescriptions, health_records, notifications, ads).
- Dual-AZ ECS desired count 2; ALB health `/healthz`.

#### Findings
| ID | Severity | Confidence | Finding | Evidence | Remediation |
|----|----------|------------|---------|----------|-------------|
| ARCH-01 | **High** | Confirmed | In-memory rate limiter breaks horizontal fairness | `security.js` Map | Shared Redis/WAF |
| ARCH-02 | Medium | Med | SPOF concentration on gateway + Functions OTP/payments | architecture | Document failover; multi-task already helps |
| ARCH-03 | Medium | High | Large unfiltered ambulance page then client filter | `frontend/lib/core/firebase/repositories/ambulance_repository.dart:381` `.limit(500)` | Server-side filters + pagination |
| ARCH-04 | Low | Med | Sequential phone candidate lookups | ambulance repository | Batch/`or` query |
| ARCH-05 | Info | High | Demo/real isolation design is strong | `demo_routing.js`; client hints rejected | Keep allowlists server-only |
| ARCH-06 | Medium | High | Stateless gateway good except rate-limit state | server design | Externalize limiter only |

Microservices split is **not** recommended without evidence of team/org need; fix horizontal concerns first.

---

### AUDIT 5: Performance & Resource

**Objective:** Static performance risks only.  
**Status:** Complete. **No profiling/load testing performed.**

| ID | Severity | Confidence | Finding | Evidence | Notes |
|----|----------|------------|---------|----------|-------|
| PERF-01 | Medium | High | Large clinical assets (ICD/medicines gz + fonts) | `frontend/assets/` | Ensure only gz ships; lazy load if needed |
| PERF-02 | Medium | High | List endpoints with hard caps, limited cursors | `supabase_health_records_repository.dart:31,57` `.limit(100)`; `ambulance_repository.dart:381` `.limit(500)`; `supabase_lab_repository.dart:150` `.limit(200)` | Adopt cursor `DataPage` everywhere |
| PERF-03 | Medium | Med | Heavy dependency surface | Firebase + Supabase + Razorpay + PDF | Periodic audit |
| PERF-04 | Medium | Med | Broad `.select()` usage | supabase repos | Column projection |
| PERF-05 | Low | High | Image downsample + `compute()` for ICD/encrypt | helpers exist | Prefer consistently |

**Unverified runtime:** endpoint latency, memory, FPS, battery — not measured.

---

### AUDIT 6: Testing & Reliability

**Objective:** Inventory tests, CI wiring, reliability gaps.  
**Status:** Complete. **No tests executed this run.**

#### Inventory
| Area | Approx. files |
|------|---------------|
| `frontend/test` | 95 `*test*.dart` |
| `backend/functions/test` | 92 `*.test.js` |
| `services/api-gateway/test` | 5 |
| `scripts/test` | 28 |

#### CI
| Workflow | Runs |
|----------|------|
| `flutter-ci.yml` | analyze + test |
| `backend-functions-ci.yml` | `npm test` + audit (path-filtered) |
| `gateway_ci.yml` | node tests + audit + Docker build (`push: false`) |
| `env-policy.yml` | env checks |
| `build-apk.yml` | APK artifact |
| `supabase-keepalive.yml` | ops ping |

**Gap:** `scripts/test` and RLS harnesses are **not** wired into GitHub Actions.

#### Historical artifacts (not this-run)
- `frontend/test_results.json` — mixed failures (historical).
- `frontend/test_results_clean.json` — reported all success historically.

| ID | Severity | Finding | Remediation |
|----|----------|---------|-------------|
| TEST-01 | Medium | scripts/test not in CI | Add job |
| TEST-02 | Medium | RLS harness not CI-gated | Gate PRs |
| TEST-03 | Medium | No Flutter Razorpay helper tests | Add mocked unit tests |
| TEST-04 | Low | Path-filtered Functions CI can skip | Required checks matrix |
| TEST-05 | Low | Emulator rules suites mostly local | Schedule optional |
| TEST-06 | Info | Do not trust historical JSON as green gate | Rely on live CI |
| TEST-07 | Medium | High | No regression test for confirm-phase recordId/booking IDOR | `s3_storage.test.js:382–408` covers upload ownership; `1162–1179` tests prefix mismatch only — **no** test for same-prefix + wrong `recordId`/`booking_id` on Supabase `.update()` path (SEC-01/02) | Add confirm tests for cross-booking/cross-record updates |

#### Strengths
OTP, webhook HMAC, gateway allowlist, Firestore/storage deny-rule emulator coverage is comparatively strong. Upload-phase lab booking ownership is tested (`s3_storage.test.js:382–408`).

---

### AUDIT 7: Compliance, Privacy & License

**Objective:** Technical privacy/license observations — **not legal advice**.  
**Status:** Complete.

#### Data collected (schema/code evidence)
PII: names, emails, mobiles, addresses, photos. PHI: prescriptions, vitals, diagnoses, health_records, lab reports. KYC: council/license numbers, document S3 keys, bank-related private fields.

#### Findings
| ID | Severity | Confidence | Finding | Evidence | Remediation |
|----|----------|------------|---------|----------|-------------|
| PRIV-01 | Medium | Med | `deleteMyAccount` exists but soft-fails / retains some commerce/clinical history | `delete_my_account.js:1057–1059` documents preserved shared records; exported `index.js:1324+` | Document retention vs erasure; surface status to users |
| PRIV-02 | Medium | High | Auth UX emphasizes Terms more than Privacy | `unified_mobile_auth_screen.dart:580–589` (Terms link only); `unified_auth_intro_screen.dart:704` | Link Privacy + Terms; store consent version |
| PRIV-03 | Medium | Med | Privacy copy under-names Razorpay/MSG91/AWS; still cites Firebase Storage for lab reports | `medibond_legal_content.dart:536` (“Google Firebase Storage” for lab reports; runtime is AWS S3 presign) | Update subprocessors + storage description |
| PRIV-04 | Medium | High | No root `LICENSE`; gateway `UNLICENSED`; Flutter `publish_to: none` | manifests | Add proprietary LICENSE; font OFL notices |
| PRIV-05 | Low | High | No Firebase Analytics / Mixpanel in pubspec | pubspec | Gate future analytics behind consent |
| PRIV-06 | Info | Med | DPDP/GDPR-style gaps (observation) | consent ledger, DPO contact absent in code | Product/legal review |

#### Regulatory note
India DPDP Act / GDPR **applicability** depends on processing context and residency. This audit identifies **potential compliance gaps** (transparency, erasure completeness, subprocessors) and does **not** assert a legal violation.

#### Strengths
Role-specific in-app Privacy/ToS; account deletion callable; sensitive doctor fields isolated table + RLS.

---

### AUDIT 8: UI/UX & Accessibility

**Objective:** Source-code UX/a11y review. **No screenshots / running app.**  
**Status:** Complete (source-only).

| ID | Severity | Confidence | Finding | Evidence | Remediation |
|----|----------|------------|---------|----------|-------------|
| UX-01 | **High** | Confirmed | Semantics almost unused (1 file in `frontend/lib` matches `Semantics(`/`semanticLabel`: `patient_picker_sheet.dart`) | repo-wide grep | Label shells, CTAs, icons |
| UX-02 | Medium | Med | Many hardcoded `Color(0x…)` despite tokens (~130+ files under `frontend/lib` contain `Color(0x`) | `app_colors.dart` vs feature screens | Prefer tokens; contrast QA |
| UX-03 | Medium | High | Global Inter font | `app_theme.dart`, pubspec | Keep if brand-locked; else brand typeface + attribution |
| UX-04 | Low | High | Loading/empty patterns uneven | shared empty widgets + ad-hoc spinners | Standardize |
| UX-05 | Low | High | Form validation present on key flows | edit profile / validators | Extend to KYC/booking consistently |
| UX-06 | Low | High | Moderate responsive usage | LayoutBuilder/MediaQuery counts | Continue web layouts |
| UX-07 | Info | Med | Imperative Navigator, no GoRouter | splash/dashboard/auth | Document IA; consider deep-link router |

#### Strengths
Theme controller; role empty states; auth legal links; about-screen privacy entry.

---

### AUDIT 9: DevOps, CI/CD & Infrastructure

**Objective:** CI/CD, Terraform, secrets, monitoring, production readiness.  
**Status:** Complete. No deploy/destructive commands run.

#### Findings
| ID | Severity | Confidence | Finding | Evidence | Remediation |
|----|----------|------------|---------|----------|-------------|
| DEVOPS-01 | **High** | High | Gateway image omits dependency install while revocation needs `firebase-admin` | Dockerfile + `firebase_revocation.js` | Fix image; smoke auth |
| DEVOPS-02 | Medium | High | CloudWatch alarms lack `alarm_actions`/SNS | `cloudwatch.tf:12–45` | Attach SNS/PagerDuty |
| DEVOPS-03 | Medium | High | No ALB HTTP→HTTPS redirect listener (443 only) | `infra/aws/alb.tf:42–54` defines HTTPS listener on 443 only — no port-80 redirect resource in file | Add redirect listener if HTTP:80 is exposed |
| DEVOPS-04 | Medium | High | No CI/CD for Terraform apply / ECR push / Firebase deploy | workflows | Controlled CD + approvals |
| DEVOPS-05 | Medium | Med | RDS backups/PITR not in Terraform; checklist unchecked | `rds.tf`, pre-launch checklist | Codify + restore drill |
| DEVOPS-06 | Medium | High | Staging/prod may share Firebase/S3/Redis | `ENVIRONMENTS.md` | Split before PHI scale |
| DEVOPS-07 | Low | High | ECS missing `APP_ENV` | `ecs.tf:78–83` | Inject production |
| DEVOPS-08 | Low | Med | Config defaults for JWT/anon if secrets missing | `config.js:21–24` | Fail closed |
| DEVOPS-09 | Info | High | WAF not applied from CI | `waf.tf` comments | Track drift |

#### Strengths
Secrets Manager bindings; TLS 1.3; WAF managed rules; SG least privilege; ALB deletion protection; env policy CI; dual-container healthchecks.

#### Deployment failure risks
Mis-deployed gateway without secrets → JWT default risk; missing S3 exports → upload outage; incomplete migration → RLS gaps; no alarm paging → prolonged downtime unnoticed.

---

## 6. Findings Register

| ID | Audit | Finding | Severity | Confidence | File | Status |
|----|-------|---------|----------|------------|------|--------|
| SEC-01 | Security | Lab report confirm IDOR | HIGH | CONFIRMED | `backend/functions/s3_storage.js` | Open |
| SEC-02 | Security | Health-record confirm IDOR | HIGH | CONFIRMED | `backend/functions/s3_storage.js` | Open |
| SEC-03 | Security | Default PostgREST JWT secret | HIGH | HIGH | `services/api-gateway/src/config.js` | Open |
| SEC-04 | Security | Revocation not fail-closed / APP_ENV | MEDIUM | HIGH | `config.js` / `ecs.tf` | Open |
| SEC-05 | Security | Ambulance HTTP App Check default off | MEDIUM | CONFIRMED | `http_endpoint_security.js` | Open |
| SEC-06 | Security | app_role claim fallback | MEDIUM | HIGH | `token_verifier.js` | Open |
| SEC-07 | Security | Broad CSP connect-src | MEDIUM | CONFIRMED | `firebase.json` | Open |
| SEC-08 | Security | In-memory rate limits | LOW | CONFIRMED | `security.js` | Open |
| SEC-09 | Security | MIME without magic sniff | LOW | CONFIRMED | `s3_storage.js` | Open |
| SEC-10 | Security | S3 callables not exported | HIGH | CONFIRMED | `index.js` / `s3_storage.js` | Open |
| SEC-11 | Security | XFF leftmost on ambulance HTTP | LOW | CONFIRMED | `index.js` | Open |
| SEC-12 | Security | Demo UID prefix routing | LOW | HIGH | `demo_routing.js:65–68` | Open |
| SEC-13 | Security | Gateway missing security headers | LOW | CONFIRMED | `server.js:121–133` | Open |
| DEP-01 | Dependencies | `timezone: any` | MEDIUM | HIGH | `pubspec.yaml` | Open |
| DEP-02 | Dependencies | Missing lockfiles | MEDIUM | HIGH | root/scripts/proxy | Open |
| DEP-03 | Dependencies | Gateway Docker no npm install | HIGH | HIGH | `Dockerfile` | Open |
| DEP-04 | Dependencies | firebase-admin major skew | MEDIUM | HIGH | lockfiles | Open |
| DEP-05 | Dependencies | Gateway CI without npm ci | LOW | MED | `gateway_ci.yml` | Open |
| DEP-06 | Dependencies | Node 20 vs 22 CI skew | LOW | MED | `backend-functions-ci.yml` | Open |
| DEP-07 | Dependencies | CVE not re-verified | INFO | HIGH | — | N/A |
| DEP-08 | Dependencies | MSG91 proxy unlocked install | LOW | MED | proxy Dockerfile | Open |
| CQ-01 | Quality | S3 export wiring (see SEC-10) | HIGH | CONFIRMED | `index.js` | Verified (Audit 3) |
| CQ-02 | Quality | Mega modules/screens | MEDIUM | HIGH | multiple | Open |
| CQ-03 | Quality | Hardcoded invite URLs | MEDIUM | HIGH | `app_web_urls.dart` | Fixed |
| CQ-04 | Quality | Duplicated deletion UX | MEDIUM | MED | `delete_account_flow.dart` | Fixed |
| CQ-05 | Quality | Low TODO debt | LOW | HIGH | lib/functions | Info |
| CQ-06 | Quality | Brand naming mix | LOW | MED | `BRAND_NAMING_ALIASES.md` | Documented |
| ARCH-01 | Architecture | In-memory rate limit scale | HIGH | CONFIRMED | `security.js` | Open |
| ARCH-02 | Architecture | Gateway/Functions SPOF | MEDIUM | MED | architecture | Open |
| ARCH-03 | Architecture | Ambulance over-fetch | MEDIUM | HIGH | repository | Open |
| ARCH-04 | Architecture | Sequential phone lookups | LOW | MED | repository | Open |
| ARCH-05 | Architecture | Demo/real isolation strength | INFO | HIGH | `demo_routing.js` | Strength |
| ARCH-06 | Architecture | Gateway mostly Stateless | MEDIUM | HIGH | gateway | Open |
| PERF-01 | Performance | Large assets | MEDIUM | HIGH | `assets/` | Open |
| PERF-02 | Performance | Pagination/cursor gaps | MEDIUM | HIGH | repos | Open |
| PERF-03 | Performance | Heavy deps | MEDIUM | MED | pubspec | Open |
| PERF-04 | Performance | Broad selects | MEDIUM | MED | repos | Open |
| PERF-05 | Performance | Image/compute helpers | LOW | HIGH | helpers | Strength |
| TEST-01 | Testing | scripts/test not in CI | MEDIUM | HIGH | workflows | Open |
| TEST-02 | Testing | RLS harness not CI | MEDIUM | HIGH | scripts/db | Open |
| TEST-03 | Testing | Flutter Razorpay untested | MEDIUM | HIGH | frontend | Open |
| TEST-04 | Testing | Path-filtered CI gaps | LOW | HIGH | workflows | Open |
| TEST-05 | Testing | Emulator suites local | LOW | MED | package.json | Open |
| TEST-06 | Testing | Historical results only | INFO | HIGH | test_results*.json | N/A |
| TEST-07 | Testing | Confirm IDOR regression gap | MEDIUM | HIGH | `s3_storage.test.js` | Open |
| PRIV-01 | Privacy | Deletion soft-fail/retention | MEDIUM | MED | `delete_my_account.js` | Open |
| PRIV-02 | Privacy | Consent UX Terms-heavy | MEDIUM | HIGH | auth screen | Open |
| PRIV-03 | Privacy | Subprocessors / Storage copy | MEDIUM | MED | legal content | Open |
| PRIV-04 | License | Missing LICENSE | MEDIUM | HIGH | repo root | Open |
| PRIV-05 | Privacy | No product analytics SDK | LOW | HIGH | pubspec | Info |
| PRIV-06 | Privacy | DPDP/GDPR gap observations | INFO | MED | — | Open |
| UX-01 | UI/UX | Near-zero Semantics | HIGH | CONFIRMED | `frontend/lib` | Open |
| UX-02 | UI/UX | Hardcoded colors | MEDIUM | MED | screens | Open |
| UX-03 | UI/UX | Inter as global default | MEDIUM | HIGH | theme | Open |
| UX-04 | UI/UX | Uneven loading/empty | LOW | HIGH | screens | Open |
| UX-05 | UI/UX | Form validation coverage | LOW | HIGH | forms | Open |
| UX-06 | UI/UX | Responsive coverage | LOW | HIGH | layouts | Open |
| UX-07 | UI/UX | Navigator IA | INFO | MED | routing | Open |
| DEVOPS-01 | DevOps | Gateway image deps | HIGH | HIGH | Dockerfile | Open |
| DEVOPS-02 | DevOps | Alarms without SNS | MEDIUM | HIGH | `cloudwatch.tf` | Open |
| DEVOPS-03 | DevOps | No HTTP→HTTPS redirect | MEDIUM | HIGH | `alb.tf` | Open |
| DEVOPS-04 | DevOps | No deploy CD | MEDIUM | HIGH | workflows | Open |
| DEVOPS-05 | DevOps | Backup not in IaC | MEDIUM | MED | `rds.tf` | Open |
| DEVOPS-06 | DevOps | Shared staging/prod tenants | MEDIUM | HIGH | ENVIRONMENTS.md | Open |
| DEVOPS-07 | DevOps | Missing APP_ENV on ECS | LOW | HIGH | `ecs.tf` | Open |
| DEVOPS-08 | DevOps | Config secret defaults | LOW | MED | `config.js` | Open |
| DEVOPS-09 | DevOps | WAF apply drift | INFO | HIGH | `waf.tf` | Open |

**Approximate severity counts (unique IDs in register, excluding Strength-only rows):**  
CRITICAL: **0** · HIGH: **10** · MEDIUM: **31** · LOW: **19** · INFO: **8**

---

## 7. Critical & High-Risk Findings

No finding was classified **CRITICAL** under this audit’s bar (no confirmed unauthenticated RCE, mass credential dump, or verified live secret in git). The following **HIGH** items require immediate remediation before trusting production PHI workflows.

### SEC-01 — Lab report confirm IDOR
See Audit 1. Any authenticated lab can update another lab’s booking report pointer via service-role client without ownership filter.

### SEC-02 — Health-record confirm IDOR
See Audit 1. Prefix ownership ≠ row ownership on `record_id` update.

### SEC-03 — Default PostgREST JWT secret
See Audit 1 / `config.js:21`. Fail closed; rotate if ever used.

### SEC-10 / CQ-01 — S3 callables not exported
`s3_storage.js` defines onCall handlers; `index.js` does not re-export them; Flutter still invokes them. Confirm live Firebase function list and fix wiring.

### DEP-03 / DEVOPS-01 — Gateway Docker without dependencies
Image intentionally copies only `src/` + `package.json`. Revocation path `require('firebase-admin/…')` soft-fails when Admin unavailable unless `required=true` (needs `APP_ENV=production`). Combined misconfig disables revocation silently.

### ARCH-01 — In-memory rate limiting
ECS desired count >1 dilutes abuse controls unless WAF compensates (WAF exists but apply state not verified from this checkout alone).

### UX-01 — Accessibility Semantics gap
Near-absent Semantics labels create major a11y debt for Play/App Store and inclusive use (source-verified).

---

## 8. Architecture & Data Flow Analysis

### Major modules
- **Frontend roles:** patient, doctor, lab, pharmacy, ambulance, admin (+ promoted ads, onboarding).
- **Functions:** OTP/auth, appointments, Razorpay/ads, S3 (intended), admin platform, FCM/outbox, webhooks, delete account.
- **Gateway:** CORS → auth (service/Firebase/anon) → allowlist → mint JWT → proxy PostgREST.
- **DB:** public tables + private helpers; `anon` / `authenticated` / `service_role` / `authenticator`.

### Authentication flow
1. OTP / registration via Cloud Functions.
2. Custom claims: `role: authenticated`, `app_role` / `user_role`.
3. Flutter Supabase client attaches Firebase ID token.
4. Gateway verifies Firebase JWT (JWKS ± revocation).
5. Mints 60s PostgREST JWT with `sub` = Firebase UID.
6. RLS enforces ownership via `auth.jwt()->>'sub'`.

### Critical data flows
| Flow | Path |
|------|------|
| Appointments | Client RPC `book_appointment_atomic` and/or CF callables |
| KYC | S3 uploads + admin verification; DB locks after verified |
| Payments | Razorpay order → verify/webhook; tables service-role-only at gateway |
| Medical files | S3 keys on health_records / lab bookings (confirm path buggy) |

### Bottlenecks & architecture risks
- Gateway + Functions OTP as choke points.
- In-memory rate limits.
- Large Flutter screens and Functions modules slow safe change.
- Shared cloud tenants staging/prod (documented).

---

## 9. Security Risk Summary

| Tier | Items |
|------|-------|
| Critical | None confirmed this run |
| High | SEC-01, SEC-02, SEC-03, SEC-10, DEP-03/DEVOPS-01, ARCH-01 (scale abuse) |
| Medium | SEC-04–07, PRIV-01–04, DEVOPS-02–06, others per register |
| Low | SEC-08–09, SEC-11–12, assorted hygiene |

### Security strengths
Deny-all client Firebase data planes; gateway allowlists; RLS; secret hygiene; hosting headers; admin approval allowlist; Razorpay signature checks.

### Recommended security action plan
1. **P0:** Patch S3 confirm IDORs; fix S3 exports; fail-closed JWT secret; fix gateway image + `APP_ENV`.
2. **P1:** App Check on ambulance HTTP; claim fallback; CSP tighten; shared rate limit.
3. **P2:** Magic-byte sniff; XFF alignment; demo routing hardening; SCA (CVE) re-run.

---

## 10. Performance & Scalability Summary

| Area | Assessment |
|------|------------|
| Current bottlenecks (static) | Large assets; list over-fetch; mega UI builds |
| Scaling problems | In-memory rate limits; PostgREST pool size 10 in ECS task env |
| Performance risks | Unpaginated growth tables; wide selects |
| Improvements | Cursor pagination; Redis rate limit; asset/lazy ICD |
| Unverified | All latency/FPS/memory claims |

---

## 11. Testing & Reliability Summary

| Topic | Result |
|-------|--------|
| Existing tests | ~220 test files across Flutter/Functions/gateway/scripts |
| Tests executed this audit | **None** |
| Results | N/A |
| Missing tests | Flutter Razorpay UX; CI for scripts/RLS; **confirm-phase** S3 IDOR tests (TEST-07; upload ownership covered) |
| Reliability risks | Alarms without paging; soft-fail deletion; S3 wiring |
| Strategy | Keep rules/OTP suites; add ownership regression tests; CI for scripts + RLS |

---

## 12. Compliance & Privacy Summary

| Topic | Notes |
|-------|-------|
| Privacy risks | PHI in Postgres/S3; confirm IDOR integrity; legal copy drift vs architecture |
| Potential compliance gaps | Subprocessor disclosure; consent versioning; erasure completeness |
| Third-party handling | Firebase, AWS, Razorpay, MSG91, Redis, Supabase |
| License risks | No root LICENSE; gateway UNLICENSED; font attribution needs review |
| Limitations | Not a legal opinion; processors’ DPAs not inspected |

---

## 13. DevOps & Production Readiness

| Area | Assessment |
|------|------------|
| CI/CD | Strong check-only; no automated prod deploy |
| Deployment | Manual Firebase/ECS; gateway image incomplete for Admin |
| Infrastructure | Mature Terraform edge; RDS instance external to TF |
| Backup | Runbook/checklist oriented; not IaC-verified here |
| Rollback | ECS previous task + SQL runbooks documented |
| Monitoring | Logs + alarms without notification actions |
| Environment handling | Strong `.env.example` + env CI; APP_ENV gap on ECS |
| Production risks | HIGH until S3 IDOR/wiring/JWT/Docker/`APP_ENV` addressed |

---

## 14. Prioritized Remediation Roadmap

### P0 — Immediate

| Finding ID | Action | Priority | Expected benefit | Effort | Dependencies |
|------------|--------|----------|------------------|--------|--------------|
| SEC-01 | Ownership check on lab_reports confirm | P0 | Stop cross-lab PHI pointer overwrite | S | Staging test account |
| SEC-02 | Ownership check on health_records confirm | P0 | Stop cross-patient record corruption | S | Same |
| SEC-10 | Export S3 callables from `index.js` + redeploy | P0 | Restore/align upload path | S–M | Firebase deploy access |
| SEC-03 | Fail closed on default JWT secret; rotate if needed | P0 | Prevent forged PostgREST JWTs | S | Secrets Manager |
| DEP-03 / DEVOPS-01 | Fix gateway Docker install + ECS `APP_ENV` | P0 | Enable revocation / prod posture | M | ECR push |

### P1 — Within 7 Days

| Finding ID | Action | Priority | Benefit | Effort | Dependencies |
|------------|--------|----------|---------|--------|--------------|
| SEC-04 / DEVOPS-07 | Require revocation in prod | P1 | Session kill reliability | S | ADC on ECS |
| SEC-05 | Enforce ambulance App Check | P1 | Reduce stuffing | S | Client App Check |
| SEC-06 | Fix app_role mapping | P1 | Predictable authz | S | Claim backfill |
| SEC-07 | Tighten CSP connect-src | P1 | Limit XSS exfil | M | Web QA |
| DEVOPS-02 | SNS on CloudWatch alarms | P1 | Faster incident response | S | Ops channel |
| TEST-01 / TEST-02 | CI for scripts + RLS | P1 | Prevent authz regressions | M | CI minutes |
| PRIV-03 | Update privacy subprocessors/storage copy | P1 | Transparency accuracy | S | Legal review |

### P2 — Within 30 Days

| Finding ID | Action | Priority | Benefit | Effort | Dependencies |
|------------|--------|----------|---------|--------|--------------|
| ARCH-01 / SEC-08 | Shared rate limiting | P2 | Abuse resistance at scale | M | Redis/WAF |
| CQ-02 | Split mega modules/screens | P2 | Safer changes | L | Team capacity |
| PERF-01 / PERF-02 | Assets + pagination | P2 | Client performance | M | UX QA |
| UX-01 | Semantics pass | P2 | Accessibility / store readiness | M | Design |
| DEVOPS-05 / DEVOPS-06 | Backup proof + env isolation | P2 | DR + blast-radius | L | Cloud accounts |
| PRIV-01 / PRIV-02 / PRIV-04 | Erasure clarity, consent, LICENSE | P2 | Compliance packaging | M | Legal |
| DEP-01 / DEP-02 / DEP-04 | Pin deps / locks / align admins | P2 | Supply-chain hygiene | S–M | — |

### P3 — Within 60–90 Days

| Finding ID | Action | Priority | Benefit | Effort | Dependencies |
|------------|--------|----------|---------|--------|--------------|
| SEC-09 | Magic-byte / malware scan on uploads | P3 | Upload integrity | M | Pipeline |
| DEVOPS-04 | Controlled CD with approvals | P3 | Deploy reliability | L | Org process |
| UX-02 / UX-03 | Token/typography consistency | P3 | Design quality | M | Brand |
| ARCH-03 / ARCH-04 | Query efficiency | P3 | Scale | M | — |
| PERF-03 | Dependency slim-down | P3 | Bundle/startup | M | — |
| Full SCA | Monthly CVE review | P3 | Known vulns | S | Tooling |

---

## 15. Suggested Future Audit Plan

| Trigger | Recommendation |
|---------|----------------|
| Before production releases | Diff-scoped security + RLS + gateway allowlist review |
| Monthly | Dependency SCA (`npm audit`/OSV/pub); secret scan |
| Quarterly | Full 9-type audit refresh |
| After major architecture changes | Auth/data-plane re-audit |
| After adding sensitive data flows | Privacy + encryption + retention review |
| After security incidents | Focused threat-model + regression tests |
| After S3/export fixes | Targeted IDOR retest in staging |

---

## 16. Audit Limitations

- **Not inspected exhaustively:** every Flutter screen visually; every SQL migration line-by-line; all `node_modules`; historical git secret history beyond current tree + README warning.
- **External services not verified:** live Firebase deploy set, Razorpay dashboard, MSG91 caps, RDS PITR console, WAF association state, Secrets Manager values.
- **Runtime tests not executed:** unit/integration/e2e, load, browser a11y, mobile profiling.
- **Infrastructure not accessible:** no AWS/GCP login in this audit.
- **Security testing limitations:** static analysis only; no adversarial network tests.
- **Assumptions:** Terraform reflects intended prod topology; Firestore deny-all is deployed; Flutter talks to gateway URL from env/dart-defines.

---

## 17. Final Verdict

| Question | Assessment |
|----------|------------|
| Is the codebase production-ready? | **Not yet for full PHI production confidence.** Foundation is strong, but HIGH issues in S3 confirm authorization, S3 Function wiring, JWT fail-open default, and gateway container/`APP_ENV` posture must be closed first. |
| What must be fixed before production? | SEC-01, SEC-02, SEC-10, SEC-03, DEP-03/DEVOPS-01 (plus verification of revocation and deploy lists). |
| What to prioritize next? | P0 security patches → P1 App Check/CSP/alarms/CI gates → P2 scale, a11y, privacy packaging. |
| Overall risk level | **HIGH** |
| What should the team do next? | 1) Patch confirm IDORs + export S3 callables. 2) Harden gateway secrets/Docker/`APP_ENV`. 3) Run staging IDOR + upload smoke. 4) Wire scripts/RLS into CI. 5) Update privacy subprocessors. 6) Schedule CVE scan. |

---

## 18. Nine-Audit Completion Checklist

| # | Audit | Completion | Evidence inspected this pass | Gaps / not verified |
|---|-------|------------|------------------------------|---------------------|
| 1 | Security & Vulnerability | **Complete** | `s3_storage.js`, `index.js`, gateway `src/`, rules, `firebase.json`, `promoted_ads.js` webhook | Live exploit, deployed function list, WAF live state |
| 2 | Dependency & Supply Chain | **Complete** | Manifests, lockfiles, Dockerfiles, CI YAML | CVE/OSV scan not run |
| 3 | Code Quality & Maintainability | **Complete** | Prior LOC table (no re-count); wiring + invite URLs | Full dead-code trace not performed |
| 4 | Architecture & Scalability | **Complete** | Gateway, demo routing, repos, `ENVIRONMENTS.md` | Runtime load / pool saturation |
| 5 | Performance & Resources | **Complete** | Static: assets, repo `.limit()`, pubspec | Profiling, bundle size build |
| 6 | Testing & Reliability | **Complete** | Test file counts, CI workflows, `s3_storage.test.js` gaps | **No tests executed**; coverage % not collected |
| 7 | Compliance, Privacy & License | **Complete** | `medibond_legal_content.dart`, `delete_my_account.js`, manifests | Legal review; DPA/subprocessor contracts |
| 8 | UI/UX & Accessibility | **Complete (source-only)** | Semantics/Color greps, auth/legal screens | No screenshots; no TalkBack/VoiceOver run |
| 9 | DevOps, CI/CD & Infrastructure | **Complete** | Terraform `infra/aws/*`, workflows, Dockerfile | No `terraform plan`; no AWS console |

### Findings by severity (register IDs)

| Severity | Count |
|----------|------:|
| CRITICAL | 0 |
| HIGH | 10 |
| MEDIUM | 31 |
| LOW | 19 |
| INFO | 8 |
| **Total tracked** | **68** |

### Remaining limitations (unchanged in substance)
- Production deploy inventory (which Cloud Functions are live) is **NEEDS VALIDATION** for SEC-10.
- CVE/supply-chain risk uses declared versions only.
- Performance and UX runtime behavior unmeasured.
- No slow PowerShell recursive line-count was run (per instruction).

---

---

## 19. Security Remediation Addendum (Audit 1 — SEC-01 … SEC-13)

> **Note:** This section documents **post-audit remediation** (2025-11-25). Original finding text above is unchanged. Authoritative implementation detail: `SECURITY_AUDIT_1_REMEDIATION_REPORT.md`.

| ID | Post-remediation status | Evidence |
|----|-------------------------|----------|
| SEC-01 | **FIXED** | `assertLabReportConfirmOwnership`, constrained `lab_bookings` update |
| SEC-02 | **FIXED** | `assertHealthRecordConfirmOwnership`, constrained `health_records` update |
| SEC-03 | **FIXED** | `assertGatewayProductionConfig()` on gateway boot |
| SEC-04 | **BLOCKED** (staging) | In-repo **FIXED**; staging revoke e2e **not verified** (`audit1_staging_prereq_check.js` exit 2) |
| SEC-05 | **FIXED** | Production default App Check enforce in `http_endpoint_security.js` |
| SEC-06 | **FIXED** | `token_verifier.js` — no generic `role` fallback |
| SEC-07 | **BLOCKED** (staging) | Local CSP validation complete; **hosted staging browser gate not run** |
| SEC-08 | **BLOCKED** (staging) | Local Redis multi-instance integration complete; **ECS staging gate not run** |
| SEC-09 | **FIXED** | Magic-byte validation on confirm |
| SEC-10 | **FIXED** (repo) | S3 callables re-exported from `index.js` |
| SEC-11 | **FIXED** | `scripts/lib/trusted_client_ip.js` |
| SEC-12 | **FIXED** | Demo prefix routing disabled in production |
| SEC-13 | **FIXED** | `buildApiSecurityHeaders()` on gateway JSON responses |

**Tests run after remediation (2026-11-25 completion):** Functions `npm test` (**562 pass**, 23 skipped); Gateway `npm test` (**121 pass**, 1 skipped); Redis integration (**4 pass**); scripts (**10 pass**); CSP unit + HTTP smoke (**14 pass**); `flutter build web` (**pass**); limited browser load under CSP (**login shell**).

**Closure:** `SECURITY_AUDIT_1_FINAL_CLOSURE_REPORT.md` — **Audit 1 NOT CLOSED** (SEC-04/07/08 staging **BLOCKED**). Prereq: `node scripts/security/audit1_staging_prereq_check.js`.

**Audit 2 (2026-11-26):** Branch `audit2/docker-ci-evidence` pushed (`e9c42b7` + `081ae77`); see `AUDIT_2_REPORT.md` §§10–11 (**OPEN** — local verification complete; **GHA/Docker not evidenced**; workflow does not run on feature-branch push). Audit 1 status unchanged.

**Staging checklist:** `docs/audit/SECURITY_AUDIT_1_STAGING_CHECKLIST.md`. **Continuation detail:** `SECURITY_AUDIT_1_REMEDIATION_REPORT.md` §6–7.

---

## 20. Audit 3 — Code quality remediation (2026-11-26)

**Status:** **PARTIALLY COMPLETE** — see `AUDIT_3_REPORT.md` and `docs/audit/AUDIT_3_CHECKLIST.md`.

| CQ | Post-remediation status |
|----|-------------------------|
| CQ-01 | **VERIFIED** — S3 callables re-exported from `index.js` (SEC-10 overlap; Audit 1 not closed) |
| CQ-02 | **OPEN** — `cross_role_sync.js` (~4294 LOC) split deferred |
| CQ-03 | **FIXED** — `AppWebUrls` / `PUBLIC_WEB_ORIGIN` |
| CQ-04 | **FIXED** — `delete_account_flow.dart` |
| CQ-05 | **INFO** — low TODO debt retained |
| CQ-06 | **DOCUMENTED** — `docs/audit/BRAND_NAMING_ALIASES.md` |

**Tests:** `flutter analyze --no-pub` clean; 14 Flutter unit tests; `s3_callables_exports.test.js` pass.

---

*End of report. Sections 1–18 are the original read-only audit record. Section 19 records Audit 1/2 remediation validation. Section 20 records Audit 3.*
