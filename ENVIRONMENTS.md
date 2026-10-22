# DoctorNect: Environment Architecture & Configuration Guide

**Document Version:** 1.0.0  
**Environments:** Staging (`staging`) vs Production (`production`)  
**Target Architecture:** Firebase Auth + Supabase PostgreSQL + AWS S3 + Redis

---

## 1. Overview & Isolation Principles

DoctorNect maintains **two strictly isolated environments**: **Staging** and **Production**. Under zero circumstances should staging and production share database instances, S3 storage buckets, Firebase user pools, payment gateway keys, or encryption secrets.

### Isolation Matrix

| Component | Staging Environment (`staging`) | Production Environment (`production`) | Enforcement Mechanism |
|---|---|---|---|
| **Supabase Project** | Dedicated staging project (`irpkyedfmdsuvapfnrim`) | Dedicated production project (`medibond-prod` / current ref) | Separate Supabase project URL & Service Role keys |
| **PostgreSQL Database** | Staging PostgreSQL instance | Production PostgreSQL instance (with PITR enabled) | Network, project ID, and credential segregation |
| **Firebase Auth & Project** | `medibond-staging` (or staging app id) | `medibond-45fad` / `medibond-prod` | Separate `google-services.json` & `GoogleService-Info.plist` |
| **AWS S3 Storage Bucket** | `doctornect-staging-vault` | `doctornect-prod-vault` | Separate AWS IAM bucket policies & KMS CMKs |
| **Razorpay Gateway** | Test Mode (`rzp_test_*`) | Live Mode (`rzp_live_*`) | Gateway key prefix check & webhook signature keys |
| **Redis Cache** | Staging Redis cluster / db 1 | Production Redis cluster / db 0 | Separate host, port, and TLS credentials |
| **Secret Manager** | GCP Secret Manager staging path | GCP Secret Manager prod path | IAM service account role binding |
| **Client Flavor** | `staging` flavor | `prod` flavor | Android productFlavors / iOS build schemes |

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
  "SUPABASE_URL": "https://irpkyedfmdsuvapfnrim.supabase.co",
  "SUPABASE_ANON_KEY": "<STAGING_ANON_KEY>",
  "USE_SUPABASE_AUTH": "true",
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
  "SUPABASE_URL": "https://<PROD_PROJECT_REF>.supabase.co",
  "SUPABASE_ANON_KEY": "<PROD_ANON_KEY>",
  "USE_SUPABASE_AUTH": "true",
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
