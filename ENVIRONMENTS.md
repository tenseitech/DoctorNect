# DoctorNect: Environment Architecture & Configuration Guide

**Document Version:** 1.1.0  
**Environments:** Staging (`staging`) vs Production (`production`)  
**Target Architecture:** Firebase Auth + Supabase PostgreSQL + AWS S3 + Redis

---

## 0. Single source of truth (repo root)

| File | Git | Purpose |
|---|---|---|
| **`.env.example`** | Committed | Every variable name + safe placeholder; one line comment per key |
| **`.env`** | **Gitignored** | Real values for **both** staging and production (`APP_ENV` selects runtime behavior) |

All Node scripts, migration tooling, Cloud Functions (local + deploy materialization), API gateway, and Flutter release builds load **only** the repo root `.env`. Legacy paths (`.env.migration`, `backend/functions/.env`, `frontend/.env`) are removed — deploy generates a transient `backend/functions/.env` from root `.env` and deletes it after Firebase deploy.

Verification (local):

```bash
npm run env:verify
node scripts/env/verify_env_file_policy.js
```

---

## 1. Overview & Isolation Principles

DoctorNect maintains **two strictly isolated environments**: **Staging** and **Production**. Under zero circumstances should staging and production share database instances, S3 storage buckets, Firebase user pools, payment gateway keys, or encryption secrets.

### Isolation Matrix

| Component | Staging Environment (`staging`) | Production Environment (`production`) | Enforcement Mechanism |
|---|---|---|---|
| **Database** | Staging Supabase (`staging-project-ref`) | Amazon RDS PostgreSQL **18.3** (`PROD_PG_MAJOR=18`, `PROD_PG_VERSION=18.3`) | Complete database & network segregation |
| **Access Layer** | Direct Supabase PostgREST | AWS PostgREST + Node.js Auth Gateway | Independent endpoints & JWT signing |
| **Firebase Auth & Project** | `medibond-45fad` (Shared today) | `medibond-45fad` (Shared today) | Claim/role tagging & separate staging app ID recommended |
| **AWS S3 Storage Bucket** | `doctornect` (Shared today) | `doctornect-prod-vault` (Dedicated recommended) | S3 key prefix `staging/` or dedicated production bucket |
| **Razorpay Gateway** | Test Mode (`rzp_test_*`) | Live Mode (`rzp_live_*`) | Gateway key prefix check & webhook signature verification |
| **Redis Ephemeral Cache** | Redis DB 1 (or staging cluster) | Redis DB 0 (Dedicated production cluster) | Separate host/DB index & key namespace |
| **Client Target** | `staging` target / Supabase client | `prod` target / Gateway client | Flutter `--dart-define` compilation |

---

## 2. Shared Cloud Resources Risk Evaluation (Phase 3.4)

| Resource | Used by Staging | Used by Production | Isolation Today | Recommendation & Risk Assessment | Cloud Action Needed from Operator |
|---|---|---|---|---|---|
| **Firebase Project (`medibond-45fad`)** | YES | YES | **SHARED** | **High Risk:** Staging and production users reside in the same Firebase Auth user pool. A staging test user could authenticate against production unless claims are strictly verified. Recommended: Dedicated `medibond-staging` project. | Provision `medibond-staging` project in Firebase console OR register staging-specific package ID (`com.doctornect.app.staging`). (MANUAL_ACTIONS Item 4) |
| **AWS S3 Storage Bucket** | YES | YES | **SHARED** | **Critical PHI Risk:** Staging test files and production prescriptions currently land in the same S3 bucket. Cross-environment deletion or key collisions could expose patient health records. | Create dedicated production S3 bucket `doctornect-prod-vault` in `ap-south-1` with KMS SSE encryption. (MANUAL_ACTIONS Item 5) |
| **Redis / Memorystore** | YES | YES | **SHARED** | **Medium Risk:** Ephemeral rate limits, OTP sessions, and live ambulance GPS coordinates share the same cache. Cache flushes on staging would evict production sessions. | Configure separate Redis cluster or allocate Redis DB index 1 with strict key prefixing for staging. (MANUAL_ACTIONS Item 6) |
| **Firebase Cloud Functions** | YES | YES | **SHARED** | **High Risk:** Currently a single codebase is deployed to Firebase Functions. Database calls must dynamically resolve endpoints via `APP_ENV`. | Configure GCP Secret Manager for `PROD_GATEWAY_SERVICE_KEY` and `STAGING_SUPABASE_SERVICE_ROLE_KEY`. (MANUAL_ACTIONS Item 7) |
| **MSG91 SMS Gateway** | YES | YES | **SHARED** | **Low Risk:** Single DLT-registered sender ID `DRNECT`. Staging uses SMS quota. Test phones (reviewer accounts) bypass live SMS. | Verify production DLT templates and ensure SMS balance monitoring. |
| **Razorpay Gateway** | YES | YES | **LOGICALLY ISOLATED** | **Zero Risk:** Razorpay strictly enforces `rzp_test_*` vs `rzp_live_*` key segregation. Build scripts fail fast if test keys are bundled in production. | Generate live Razorpay API Key ID and Webhook Secret in dashboard. (MANUAL_ACTIONS Item 8) |

---

## 2. Configuration & Environment Variables Matrix

Every variable required by the Flutter client, Cloud Functions, and backend scripts is segregated between environments:

| Variable Name | Required By | Staging Value Format | Production Value Format | Sensitivity |
|---|---|---|---|---|
| `APP_ENV` | Flutter / Backend | `staging` | `production` | Public |
| `SUPABASE_URL` | Flutter / Functions | `https://<staging-ref>.supabase.co` | `https://<prod-ref>.supabase.co` | Public |
| `SUPABASE_ANON_KEY` | Flutter Client | Staging public anon JWT | Production public anon JWT | Public safe |
| `SUPABASE_SERVICE_ROLE_KEY` | Functions / Scripts | Staging service role secret | Production service role secret | **CRITICAL SECRET** |
| `SUPABASE_WEBHOOK_SECRET` | Functions / Supabase | Staging webhook HMAC secret | Production webhook HMAC secret | **CRITICAL SECRET** |
| `FIREBASE_PROJECT_ID` | Flutter / Functions | `medibond-staging` | `medibond-45fad` | Public |
| `FIREBASE_API_KEY_ANDROID` | Flutter (`firebase_options.dart`) | Staging Android API key | Production Android API key | App-restricted |
| `FIREBASE_API_KEY_IOS` | Flutter (`firebase_options.dart`) | Staging iOS API key | Production iOS API key | App-restricted |
| `FIREBASE_API_KEY_WEB` | Flutter (`firebase_options.dart`) | Staging Web API key | Production Web API key | Domain-restricted |
| `AWS_REGION` | Functions / Client | `ap-south-1` | `ap-south-1` | Public |
| `AWS_S3_VAULT_BUCKET` | Functions / Presign | `doctornect-staging-vault` | `doctornect-prod-vault` | Private |
| `AWS_ACCESS_KEY_ID` | Cloud Functions | Staging IAM User key | Production IAM User key | **CRITICAL SECRET** |
| `AWS_SECRET_ACCESS_KEY` | Cloud Functions | Staging IAM secret | Production IAM secret | **CRITICAL SECRET** |
| `RAZORPAY_KEY_ID` | Flutter / Functions | `rzp_test_...` (Test prefix) | `rzp_live_...` (Live prefix) | Public / Restricted |
| `RAZORPAY_KEY_SECRET` | Cloud Functions | Staging test secret | Production live secret | **CRITICAL SECRET** |
| `RAZORPAY_WEBHOOK_SECRET` | Cloud Functions | Staging test webhook secret | Production live webhook secret | **CRITICAL SECRET** |
| `REDIS_HOST` | Functions | Staging Redis endpoint | Production Redis endpoint | Private |
| `REDIS_PASSWORD` | Functions | Staging Redis password | Production Redis password | **CRITICAL SECRET** |
| `REDIS_TLS` | Functions | `true` | `true` | Private |
| `ENABLE_DEMO_AUTH` | Flutter Client | Optional (`true` in dev/staging) | **STRICTLY FALSE (Enforced by build guard)** | Build security |
| `ENABLE_DEMO_SUPER_ADMIN` | Flutter Client | Optional (`true` in dev/staging) | **STRICTLY FALSE (Enforced by build guard)** | Build security |

---

## 3. Flutter Environment Selection Mechanism

The Flutter client uses compile-time environment injection via `--dart-define-from-file` or `--dart-define` flags.

### 3.1 Environment Definition Files

Configuration files are maintained in JSON format for compile-time injection:

#### Staging Configuration: `frontend/config/env.staging.json`
```json
{
  "APP_ENV": "staging",
  "SUPABASE_URL": "https://staging-project-ref.supabase.co",
  "SUPABASE_ANON_KEY": "<STAGING_ANON_KEY>",
  "USE_S3_STORAGE": "true",
  "USE_SUPABASE_DB_DOCTOR_PATIENT": "true",
  "FIREBASE_API_KEY_ANDROID": "<STAGING_ANDROID_KEY>",
  "FIREBASE_API_KEY_IOS": "<STAGING_IOS_KEY>",
  "FIREBASE_API_KEY_WEB": "<STAGING_WEB_KEY>",
  "RAZORPAY_KEY_ID": "rzp_test_StagingKey123"
}
```

#### Production Configuration: `frontend/config/env.prod.json`
```json
{
  "APP_ENV": "production",
  "SUPABASE_URL": "https://api.gateway.doctornect.example",
  "SUPABASE_ANON_KEY": "<PROD_ANON_KEY>",
  "USE_S3_STORAGE": "true",
  "USE_SUPABASE_DB_DOCTOR_PATIENT": "true",
  "FIREBASE_API_KEY_ANDROID": "<PROD_ANDROID_KEY>",
  "FIREBASE_API_KEY_IOS": "<PROD_IOS_KEY>",
  "FIREBASE_API_KEY_WEB": "<PROD_WEB_KEY>",
  "RAZORPAY_KEY_ID": "rzp_live_ProdLiveKey456"
}
```

### 3.2 Build Commands

#### Build Staging APK / Bundle:
```bash
flutter build appbundle --release \
  --flavor staging \
  --dart-define-from-file=config/env.staging.json
```

#### Build Production App Bundle:
```bash
flutter build appbundle --release \
  --flavor prod \
  --dart-define-from-file=config/env.prod.json
```

---

## 4. Demo & Seed Auth Protections

### 4.1 Build-Time Release Guard (`demo_auth_config.dart`)
To prevent test or demo authentication backdoors from ever being included in release builds, `DemoAuthConfig` enforces a compile-time assertion in `const` constructor evaluation and startup initialization:
1. If `kReleaseMode` is `true`, `DemoAuthConfig.enabled` must evaluate to `false`.
2. If `kReleaseMode` is `true`, `DemoAuthConfig.enableDemoSuperAdmin` must evaluate to `false`.
3. If `--dart-define=ENABLE_DEMO_AUTH=true` or `--dart-define=ENABLE_DEMO_SUPER_ADMIN=true` is passed to a release build, **the Dart compiler aborts compilation immediately** with a compile-time assertion error.
4. An additional runtime sanity check in `main.dart` halts execution before any widgets or network connections initialize.

### 4.2 Seed Accounts Protection (`seed_demo_accounts.js`)
`seed_demo_accounts.js` refuses execution unless:
1. `ALLOW_DEMO_SEED=1` is explicitly set in environment.
2. In production projects, it requires `CONFIRM_PROD_SEED=<exact_project_id>`.

---

## 5. Production Database Demo/Test Data Purge Script

Before opening the production database to real patients and healthcare providers, all synthetic test accounts and demo rows must be purged.

### Script: `backend/scripts/purge_demo_test_data.js`

#### Safety Features:
- **Default Dry-Run:** Running without flags performs a pure SELECT query audit and outputs exact record counts that would be affected. **Zero rows are deleted.**
- **Mandatory Confirmation Flag:** Deletion requires `--confirm-prod-purge=<PROJECT_NAME_OR_CONFIRMATION_STRING>`.
- **Never Auto-Runs:** Cannot be triggered by build scripts, CI jobs, or cron workers.
- **Transactional Rollback:** Deletes execute inside a single PostgreSQL transaction with strict foreign-key order.

#### Usage:

```bash
# 1. Audit dry-run (simulation only - safe to run anytime):
node backend/scripts/purge_demo_test_data.js --dry-run

# 2. Live purge execution (requires explicit confirmation flag):
node backend/scripts/purge_demo_test_data.js --confirm-prod-purge=doctornect-production
```

#### Targeted Demo Identifiers:
- **Demo Phone Numbers:** `9999900002` (Doctor), `9999900001` (Patient), `9999900003` (Pharmacy), `9999900004` (Lab), `9999900005` (Ambulance), `9999988888` (Super Admin).
- **Synthetic Test UIDs:** `demo_*`, `fb_uid_*`, `test_*`.
- **Test Email Domains:** `*@test.com`, `*@doctornect.com` (demo prefixes).
