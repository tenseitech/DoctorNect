# Production wiring check (Supabase / Redis / gateway)

**Status:** **Partially verified** (2026-11-01) — Supabase URL **host hashes** and fleet-wide env flags from operator verification. Per-function `updateTime` × hash matrix still needs fresh `gcloud` paste for exact cohort membership.

## Verified Supabase URL host hashes (no hostnames)

| Hash (SHA-256 hostname, first 8 hex, uppercase) | Meaning |
|--------------------------------------------------|---------|
| **40D01C23** | Current **live-legacy** Supabase REST host (often labeled **staging** in env names) — **live data store until RDS cutover**; matches `SUPABASE_URL` in `backend/functions/.env` and non-empty `STAGING_SUPABASE_URL` in `.env.migration`. **Every function redeploy through 2026-10-31** bakes this hash. Live fleet behavior matches **`APP_ENV` unset → staging** in `getDatabaseClient()` (see below). |
| **800DB356** | Legacy Supabase REST host — **2026-10-06 ~10:24Z** deploy batch. Project-wide env was repointed **~11:37Z** same day; **functions not redeployed since** keep this baked hash. |
| **D3E9A0FB** | Doc placeholder only (`STAGING_RUNBOOK` `<STAGING_PROJECT_REF>` pattern — not a live host). |

**Doc label map (hostname not printed):**

| Hash | Label in docs |
|------|----------------|
| 800DB356 | STALE_REF “stale staging ref” (CFG-01) / pre-2026-10-06-11:37Z fleet |
| 40D01C23 | STALE_REF “target production” ref (DRNECT-DB) / PROGRESS “current Supabase → STAGING” — **live-legacy data store until RDS cutover** (operator confirms live functions use this hash today) |
| D3E9A0FB | STAGING_RUNBOOK template placeholder |

## Verified deployed env flags (names only)

| Variable | Deployed fleet |
|----------|----------------|
| `APP_ENV` | **Absent** on all deployed functions |
| `FIRESTORE_FORBIDDEN` | **Absent** on all deployed functions |
| `PROD_GATEWAY_URL` | **Absent** on all deployed functions |
| `PROD_GATEWAY_SERVICE_KEY` | **Absent** on all deployed functions |

**Local migration env:** `PROD_GATEWAY_URL` is **empty** (name present, no value committed).

## Code: how `getDatabaseClient()` picks URL/key

Source: `backend/functions/src/db/client.js`

When **`APP_ENV` is unset**, it defaults to **`staging`**:

```17:32:backend/functions/src/db/client.js
function getDatabaseClient(options = {}) {
  const appEnv = (process.env.APP_ENV || 'staging').toLowerCase();
  const isProduction = appEnv === 'production';

  const url = isProduction
    ? (process.env.PROD_GATEWAY_URL || '')
    : (process.env.STAGING_SUPABASE_URL || process.env.SUPABASE_URL || '');

  const serviceKey = isProduction
    ? (process.env.PROD_GATEWAY_SERVICE_KEY || '')
    : (process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '');
```

| `APP_ENV` (after default) | URL env vars | Service key env vars |
|---------------------------|--------------|----------------------|
| **`production`** | `PROD_GATEWAY_URL` | `PROD_GATEWAY_SERVICE_KEY` |
| **else (incl. unset)** | `STAGING_SUPABASE_URL`, else `SUPABASE_URL` | `STAGING_SUPABASE_SERVICE_ROLE_KEY`, else `SUPABASE_SERVICE_ROLE_KEY` |

With deployed **`APP_ENV` absent**, runtime uses **staging** branch + baked **`SUPABASE_URL`** (hash **40D01C23** — **live-legacy** data store until RDS cutover — on recent revisions).

**Redis** — separate from `getDatabaseClient()`; see `backend/functions/src/config/redis.js` / `REDIS_*`. Per-function secret bindings: see `docs/audit/SECRETS_MIGRATION_PLAN.md`.

## Deploy cohorts & STALE_REF tiers

See **`docs/audit/DEPLOY_HASH_COHORT.md`** for tier ↔ commit ↔ **800DB356** function list and user/appointment read risk.

## Still UNVERIFIED without fresh gcloud

- Exact function name ↔ hash ↔ `updateTime` table after 2026-10-31  
- Redis host hash parity local vs deployed  
- MSG91 / Razorpay plain env vs Secret Manager per function  
