# Architecture cutover report — Postgres-only (`feature/postgres-only-architecture`)

**Date:** 2026-10-31  
**Branch:** `feature/postgres-only-architecture` (from `cleanup/structure`)

## Summary

| Area | Status |
|------|--------|
| Firestore triggers / dual-write exports | Removed from `backend/functions/index.js`; `supabaseDatabaseWebhook` is the DB webhook entry |
| Cutover flag | `isDoctorPatientSupabasePrimary()` always `true` |
| `FIRESTORE_FORBIDDEN` | Guard loaded from `index.js`; documented in `.env.example` / `docs/ENV_MATRIX.md` |
| Firestore → Supabase migration script | Removed (`backend/scripts/migrate_firestore_to_supabase.js`) |
| Flutter facades | Majority delegate to Supabase/Postgres repos; GoTrue path removed |
| Idempotent migration | Added `db/migrations/20261103000009_review_public_policies_idempotent.sql` |
| Admin module | Unchanged (documented exception) |

## Verification matrix

| Step | Result |
|------|--------|
| `flutter analyze` | **PASS** (0 errors; warnings only) |
| `flutter test` | **NOT RUN** (this session) |
| `CI=true npm test` (`backend/functions`) | **PARTIAL** — 401 pass / 71 fail (legacy Firestore rules + `cross_role_sync` suites; S3 unit suite green) |
| `npm test` (`services/api-gateway`) | **NOT RUN** |
| `node scripts/check_env_parity.js` | **NOT RUN** |
| Migrate dry-run staging | **NOT RUN** (after `20261103000009`) |
| RDS replay + RLS harness | **NOT RUN** (wrapper: `scripts/db/verify_rds_migration_parity.sh`) |
| Firestore zero-reference grep (app) | **PARTIAL** — Admin + ambulance legacy paths + promoted ads / profile stores still reference Firestore types |

## Remaining work (priority)

1. Finish **ambulance** Postgres path in `ambulance_repository.dart` and callable pin/login helpers in `index.js` (remove dead Firestore branches when `FIRESTORE_FORBIDDEN=1`).
2. Prune or rewrite **obsolete CI tests** (`cross_role_sync`, Firestore rules replay) for deny-all / postgres-only semantics.
3. Remove `cloud_firestore` from `frontend/pubspec.yaml` once grep-clean (except Admin).
4. Production env: set `PROD_GATEWAY_URL`, `FIRESTORE_FORBIDDEN=1`, Redis rate limits, IAM role for S3 (not static keys).

## Manual go-live checklist

See plan section in `postgres-only_architecture` plan — Firebase prod project, S3 buckets, Redis, ECS gateway+PostgREST, gateway secrets, production app bundle with gateway REST base URL.
