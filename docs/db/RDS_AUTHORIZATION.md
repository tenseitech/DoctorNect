# RDS authorization model (production)

DoctorNect production uses **Firebase Authentication only** for end-user identity. PostgreSQL on AWS RDS is **not** exposed with Supabase Auth (GoTrue) or the Supabase anon/service keys to mobile clients.

## Who connects to Postgres

| Actor | DB identity | How authz works |
|---|---|---|
| **Mobile / web app** | Does not connect to RDS directly | Calls **API Gateway** with Firebase ID token; gateway verifies Firebase and mints a short-lived **PostgREST JWT** (`services/api-gateway/src/jwt_minter.js`) with `role: authenticated` and claim `sub` = Firebase UID |
| **Cloud Functions / backend jobs** | Single backend DB user (or `service_role`-equivalent) via gateway or pooled connection | Application SQL + optional `set_config('request.jwt.claims', …)` when emulating a user in tests |
| **Operators / migrations** | RDS master or migration role | Runs `db/migrations/*.sql` and bootstrap scripts |

## Roles `anon` and `authenticated`

- Created in `db/rds_bootstrap/01_roles_and_extensions.sql` for **PostgREST compatibility** and parity with staging Supabase.
- **Clients never obtain the Postgres `authenticated` role via Supabase Auth** in production builds (`USE_SUPABASE_AUTH=false`, enforced in release scripts).
- On RDS, **`authenticated` is assigned only inside gateway-minted JWTs** (or test harness JWT claims), not via Supabase session APIs.

## RLS and Supabase-specific migrations

Migrations that reference `auth.jwt()`, `auth.uid()`, or grant to `anon` / `authenticated` / `service_role` must remain **idempotent on RDS**:

- Wrap grants/revokes and policy `TO anon` / `TO authenticated` in `IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '…')` blocks where appropriate.
- `auth.jwt()` / `auth.uid()` are provided by `db/rds_bootstrap/02_auth_shim.sql` on RDS.
- Extension `plpgsql_check` is optional staging tooling only; migrations use `DROP EXTENSION IF EXISTS plpgsql_check`.

## Anonymous public read surface (staging parity / gateway anon JWT)

When PostgREST runs with role `anon` (Supabase staging or gateway unauthenticated allowlist), only these relations are readable:

| Relation | Rule |
|---|---|
| `doctor_directory` | View filter `verified=true AND deactivated=false` (definer view) |
| `lab_catalog_tests` | RLS `USING (true)` for catalog rows |
| `system_config` | RLS keys `patient_module_status`, `promoted_ads` only |
| `review_public` | RLS: reviews for verified, non-deactivated doctors only |

Everything else: **no table GRANT** to `anon` and **no EXECUTE** on `public` functions.

Automated check: `node scripts/db/anon_surface_audit.js --target=staging` (or `replay` / `production`).

## Manual verification (do not run against production without change window)

```powershell
# After applying migration 20261103000008 on staging (session pooler URL, port 5432):
node scripts/db/migrate.js --target=staging --dry-run-all
# Apply when ready:
# node scripts/db/migrate.js --target=staging

node scripts/db/anon_surface_audit.js --target=staging
node scripts/db/rls_sql_harness.js --target=staging
```
