# DoctorNect repository structure

Where code and docs live after the `cleanup/structure` pass. **Do not move** load-bearing paths (`firebase.json` → `backend/functions`, `frontend/pubspec.yaml`, `db/migrations/`) without updating every reference.

## Root (minimal)

| Item | Purpose |
|------|---------|
| `README.md` | Entry point; links here |
| `ENVIRONMENTS.md` | Staging vs production env policy (kept at root for discoverability) |
| `firebase.json`, `.firebaserc` | Firebase deploy config (functions source = `backend/functions`) |
| `.env.example` | Master env template (no secrets) |
| `package.json` | Workspace stub (rules tests) |
| `frontend/` | Flutter application |
| `backend/` | Firebase rules, indexes, Cloud Functions |
| `services/` | API gateway (PostgREST proxy) |
| `db/` | SQL migrations, RDS bootstrap, PostgREST config |
| `infra/` | Terraform / AWS |
| `scripts/` | DB, ops, verify, codemods |
| `docs/` | Runbooks, audits, ops evidence, archived planning |

## `frontend/`

Flutter app: `lib/` (features by role), `test/`, platform folders (`android/`, `ios/`, `web/`, …). New UI code under `lib/features/<module>/`.

## `backend/`

| Path | Purpose |
|------|---------|
| `functions/` | Firebase Cloud Functions (Node 22) — **canonical** functions tree |
| `firestore.rules`, `firestore.indexes.json`, `storage.rules` | Firebase rules |
| `supabase/` | Supabase CLI metadata (not app runtime) |
| `gcp-msg91-proxy/` | MSG91 egress proxy |
| `scripts/` | One-off backend maintenance scripts |

There is **no** root `functions/` deploy target (legacy local `.env` only; not in git).

## `services/api-gateway/`

Node PostgREST auth gateway: `src/`, `test/`, `Dockerfile`.

## `db/`

| Path | Purpose |
|------|---------|
| `migrations/` | Ordered SQL migrations (**never rename applied files**) |
| `rds_bootstrap/` | RDS roles, `auth.jwt()` shim, compat |
| `rds_overrides/` | RDS-only drift fixes |
| `postgrest/` | Local PostgREST config |

## `scripts/`

| Path | Purpose |
|------|---------|
| `db/` | migrate, RLS harness, anon audit, schema diff, replay |
| `lib/` | env_loader, env_guard, db_connection_guard |
| `ops/` | hygiene, secret scan helpers |
| `verify/` | smoke / prod checks |
| `codemods/` | optional Firestore branch strippers (manual) |
| `e2e/` | PostgREST HTTP e2e |

## `docs/`

| Path | Purpose |
|------|---------|
| `runbooks/` | Operator runbooks (e.g. RDS migration) |
| `reports/` | Audit and harness reports |
| `db/` | DB authorization notes |
| `ops/` | Progress, manifests, JSON artifacts (`test_runs/` is local-only; gitignored) |
| `archive/planning/` | Superseded milestone/plan markdown (read-only history) |
| `checklists/` | Cutover checklists |

## `infra/`

Terraform and AWS assets (`infra/aws/`).

## Agent / IDE tooling (optional)

`.agent/`, `.agents/`, `.cursor/`, `.gemini/`, `adapters/` — editor and model helpers; not part of production deploy.

## Where to add new files

| Kind | Location |
|------|----------|
| Flutter feature | `frontend/lib/features/...` |
| Cloud Function | `backend/functions/` (+ export in `index.js`) |
| Gateway route/policy | `services/api-gateway/src/` |
| SQL migration | **new timestamp file** in `db/migrations/` only |
| Operator runbook | `docs/runbooks/` |
| Env variable | document in `.env.example` + `docs/ENV_MATRIX.md` |
| CI-only script | `scripts/` or `.github/workflows/` |
