> **Superseded (2026-11-25):** demo numbers, roles and routing are now fixed in code. The current reference is [docs/DEMO_ACCOUNTS.md](DEMO_ACCOUNTS.md). REVIEW_*_PHONES / DEMO_PHONE_NUMBERS are ignored.

# Demo → Supabase / Real → RDS routing

> **Firestore is no longer used** (removed November 2026). Data lives in PostgreSQL: the five demo
> accounts in staging Supabase, every real user in AWS RDS behind the API gateway. Firebase is used
> only for Auth, App Check, Cloud Functions, Cloud Messaging and Remote Config. Anything below that
> mentions Firestore is historical. Current state: PROJECT_ANALYSIS.md, docs/GATEWAY_DEPLOY.md.

Release-blocking: **one production app build** (`PROD_GATEWAY_URL`); data plane selected **only on the server** from Firebase identity allowlists.

## 1. Audit — current state (pre-change baseline)

| Component | What it does today | Gap |
|-----------|-------------------|-----|
| **`is_demo` (Postgres)** | Column on `public.otp_challenges` (`DEFAULT FALSE`); smoke scripts insert it. | **Not set** by Cloud Functions on live OTP path today; mostly unused for routing. |
| **Reviewer OTP bypass** | `REVIEWER_OTP_ENABLED` + `REVIEW_{ROLE}_PHONES` + `REVIEW_FIXED_OTP` + `REVIEW_ACCESS_UNTIL`; rate-limited via Redis; `registration_otp.js` `isReviewerPhone()`. | **Not** tied to data-plane routing; no guarantee demo DB-only. |
| **`seed_demo_accounts.js`** | Writes Firestore `app_config/demo_accounts` + legacy Firestore profiles; phones **9999900001–0005** (+ superAdmin **9999988888** off); seeds doctor/lab/pharmacy/ambulance UIDs. | **Maintenance only**; prod uses Postgres gateway, not Firestore for app data. |
| **`getDatabaseClient()`** | `APP_ENV=staging` → Supabase; `APP_ENV=production` → **always** `PROD_GATEWAY_URL` (RDS). | **No per-user** demo routing. |
| **Auth gateway** | Single `PGRST_URL` upstream; mints PostgREST JWT; Firebase verify. | **No** Supabase upstream for demo users. |
| **Client app** | PostgREST via gateway URL; `verify_aab_no_supabase_staging` blocks `*.supabase.co` in release AAB. | **Correct** — must stay supabase-free in binary. |
| **Demo identification (client)** | None for DB routing (good). | Need **server allowlist** only. |
| **Supabase staging data** | Read-only audit (`staging_non_demo_user_counts.js`): **1** `users` row, **0** `otp_challenges`, **0** `is_demo=true`. | Staging lightly populated; **no evidence of bulk real-user production data** in sampled DB. |

### Demo accounts (from `seed_demo_accounts.js` + reviewer env pattern)

| Role | Count | Phone (test range) | UID pattern |
|------|-------|-------------------|-------------|
| Patient | 1 | `9999900001` | (Firebase; allowlist via `DEMO_FIREBASE_UID_ALLOWLIST`) |
| Doctor | 1 | `9999900002` | `demo_user_*` or seeded `demo_doctor_*` |
| Pharmacy | 1 | `9999900003` | e.g. `EdaUG8nTgbRjGLgZGAmDi3vWwhO2` |
| Lab | 1 | `9999900004` | e.g. `vMwQMBueSVUGpef1zzrN17gfT7y2` |
| Ambulance | 1 | `9999900005` | e.g. `CTVzgkpdnjUs0uDDr5rWdVV3iWF2` |
| Super admin demo | 0 (`enableDemoSuperAdmin: false`) | `9999988888` | — |

Phones/UIDs in production docs are **masked** in audit output; maintain full list in **Secrets Manager** / Firebase Remote Config **server-only** (`DEMO_FIREBASE_UID_ALLOWLIST`).

---

## 2. Design (recommended)

### Demo identification

- **Authoritative:** `DEMO_FIREBASE_UID_ALLOWLIST` (comma-separated Firebase UIDs) + optional prefix rule `demo_*` / `demo_user_*` for seeds.
- **OTP / phone:** `REVIEW_*_PHONES` and `DEMO_PHONE_*` env keys **only** on Functions (never client); reviewer bypass **only** if phone ∈ allowlist **and** `REVIEWER_OTP_ENABLED` + expiry.
- **Never trust:** `x-demo`, `is_demo` body/query, forged JWT `app_role`.

### Gateway flow

```
Firebase ID token → verify → UID in allowlist?
  yes → DEMO_PGRST_URL + DEMO_PGRST_JWT_SECRET (Supabase PostgREST)
  no  → PGRST_URL (RDS PostgREST)
  service_role key → always RDS
  anon → RDS (public discovery on real plane unless later split)
```

- **Fail-closed:** undecided / missing demo config → **RDS** (or 503 if demo user but demo upstream unset).
- Client never receives Supabase URL or service keys.

### Cloud Functions

- `getDatabaseClient({ firebaseUid })` / `getDatabaseClientForCallable(request)`:
  - production + demo UID → `DEMO_SUPABASE_URL` + `DEMO_SUPABASE_SERVICE_ROLE_KEY`
  - else → `PROD_GATEWAY_URL` + `PROD_GATEWAY_SERVICE_KEY`
- **Redis:** `getRedisNamespaceForCallable` → `demo:` vs `real:` prefix.
- **S3:** `getObjectStoragePrefixForCallable` → `demo/` vs `prod/` (wire in `s3_storage.js` follow-up).
- **Razorpay:** demo allowlist UIDs → test keys (env `RAZORPAY_DEMO_*`); real → live keys (separate PR).

### Isolation properties

- Separate physical DBs → demo doctor never sees real patients (PostgREST + RLS on each side).
- No migration script copies Supabase → RDS user rows (`migrate_firestore_to_supabase.js` is legacy one-off doc only; no runtime copy).

### Options considered

| Option | Pros | Cons |
|--------|------|------|
| **A. Dual upstream gateway (recommended)** | Single URL; matches release binary | Two PostgREST JWT secrets |
| B. Client picks env | Simple | **Rejected** — violates single-build |
| C. Single DB + `is_demo` RLS | One cluster | **Rejected** — audit requirement |

---

## 3. Implementation (this branch)

- `scripts/lib/demo_routing.js` — shared resolution.
- `services/api-gateway/src/server.js` + `config.js` — dual upstream when `DEMO_REAL_ROUTING_ENABLED=1`.
- `backend/functions/src/db/client.js` — per-UID client selection + Redis/S3 prefix helpers.
- `scripts/audit/staging_non_demo_user_counts.js` — read-only Supabase census.
- Tests: `scripts/test/demo_routing.test.js`, `backend/functions/test/demo_real_isolation.test.js`.

### Env flags (server-only)

| Variable | Purpose |
|----------|---------|
| `DEMO_REAL_ROUTING_ENABLED=1` | Enable production split |
| `DEMO_FIREBASE_UID_ALLOWLIST` | Demo Firebase UIDs |
| `DEMO_PGRST_URL` / `DEMO_PGRST_JWT_SECRET` | Gateway → Supabase PostgREST |
| `DEMO_SUPABASE_URL` / `DEMO_SUPABASE_SERVICE_ROLE_KEY` | Functions → Supabase REST |
| `REVIEWER_OTP_ENABLED` + `REVIEW_*` | Reviewer OTP only |

---

## 4. Isolation tests (must-pass)

| ID | Requirement | Test |
|----|-------------|------|
| a | Real user never hits Supabase upstream | `demo_real_isolation.test.js` + gateway integration (UNVERIFIED live) |
| b | Demo user never hits RDS | Same + UID allowlist |
| c | Unknown UID → RDS | `resolveDataPlane` unit tests |
| d | Client hints ignored | Gateway 400 on `x-demo`; unit `assertClientRoutingHintIgnored` |
| e | OTP bypass allowlist-only | Existing `demo_bypass_removal.test.js` + reviewer gates |
| f | Cross-DB visibility | **Physical isolation** (two DBs); RLS suites per plane |
| g | delete/notifications/S3 prefixes | Helpers added; full e2e **UNVERIFIED** |
| h | No Supabase→RDS copy scripts | Grep: no runtime copy in `scripts/db/` |

---

## 5. Operations

See `scripts/smoke/MANUAL_STEPS.md` — Supabase plan keepalive, gateway secrets, allowlist rotation.

---

## 6. Status

| Area | Status |
|------|--------|
| Unit routing logic | **PASS** (`scripts/test/demo_routing.test.js` 6/6) |
| Functions client routing | **PASS** (`demo_real_isolation.test.js`) |
| Live production gateway dual-upstream | **UNVERIFIED** |
| End-to-end App Store demo login | **UNVERIFIED** |