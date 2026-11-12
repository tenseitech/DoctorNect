# RDS production cutover — operator steps

**Scope:** Move production Postgres from Supabase (staging reference) to AWS RDS with Auth Gateway + PostgREST.  
**Safety:** No destructive SQL on production without verified backup. Staging touches require explicit approval and `--confirm-live-data`.

---

## 0. Preconditions (repo)

| Item | Check |
|------|--------|
| Migrations at head | `db/migrations/` (incl. `20261112000006`, `20261113000002`–`000003`) |
| Bootstrap | `db/rds_bootstrap/01`–`04` (run `04` **after** migrations on RDS) |
| Local proof | `node scripts/db/fresh_local_parity_test.js` |
| Auth matrix | `node scripts/db/gateway_rls_authorization_suite.js` → **49/49 PASS** (5×6 + medical + gateway) |
| Service paths | `node scripts/db/service_role_paths_test.js` |
| RLS audit | `node scripts/db/rls_coverage_audit.js` |
| Real HTTP path | `node scripts/db/real_path_authorization_e2e.js` (PostgREST + Gateway) |
| Staging grant/RPC read-only | `node scripts/db/grant_matrix_audit.js --compare-staging --confirm-live-data` · `node scripts/db/rpc_body_parity_staging.js --confirm-live-data` |

**Staging verified (2026-11-12):** After `20261113000003`, read-only checks — **0** `anon`/`authenticated` grant diffs; **64** `service_role`-only staging supersets (expected); **11/11** RPC bodies normalized-match vs local replay. See [STAGING_VERIFIED_AFTER_20261113000003.md](../reports/STAGING_VERIFIED_AFTER_20261113000003.md).

**Staging Postgres:** Supabase project **PostgreSQL 15** (see `scripts/db/generate_schema_diff_breakdown.js`).  
**RDS recommendation:** `engine_version = 15.x` (match staging major; minor can be latest 15 available in region).

**PG17 vs PG15:** Local dev may use PostgreSQL 17; cached `schema_diff` may still list **11** `FUNCTION_BODY` hashes. **Live check with staging at head: 11/11 normalized MATCH** (`rpc_body_parity_staging.js`). Optional PG15 container replay for full catalog diff:

```powershell
# When Docker Desktop is running:
$env:FRESH_LOCAL_DB_NAME="doctornect_fresh_pg15"
docker run -d --name doctornect-pg15 -e POSTGRES_PASSWORD=postgres -p 5433:5432 postgres:15
$env:REPLAY_DB_URL="postgresql://postgres:postgres@127.0.0.1:5433/postgres"
node scripts/db/fresh_local_parity_test.js
node scripts/db/schema_diff.js --target=fresh_local
```

---

## 1. Create RDS instance (AWS console / Terraform)

1. Apply `infra/aws/rds.tf` (or console equivalent): PostgreSQL **15.x**, storage encrypted, multi-AZ per policy.
2. Parameter group: include `shared_preload_libraries` = `pg_stat_statements,pg_cron` and `cron.database_name` = `postgres` (reboot required for `pg_cron`).
3. Security group: ingress **5432** only from bastion, gateway VPC, or Cloud Functions VPC connector — **not** `0.0.0.0/0`.
4. Download CA bundle: `infra/aws/global-bundle.pem`.
5. Create databases: `doctornect` (prod), `doctornect_rehearsal` (optional).

Record in `repo root `.env`` (never commit):

```ini
PROD_RDS_HOST=<rds-endpoint>
PROD_RDS_PORT=5432
PROD_RDS_USER=postgres
PROD_RDS_PASSWORD=<from-secrets-manager>
PROD_RDS_DB=doctornect
PROD_RDS_SSL_ROOT_CERT=infra/aws/global-bundle.pem
REPLAY_DB_URL=postgresql://<master>@<bastion-or-ssm-tunnel>:5432/postgres
```

---

## 2. Network access (bastion or SSM)

Full Windows steps: **[RDS_PROD_TUNNEL_WINDOWS.md](./RDS_PROD_TUNNEL_WINDOWS.md)**.

**Option A — SSM port forward** (no public RDS):

```powershell
aws ssm start-session --target <instance-id> `
  --document-name AWS-StartPortForwardingSessionToRemoteHost `
  --parameters host="<rds-endpoint>",portNumber="5432",localPortNumber="15432"
```

**Option B — Bastion SSH tunnel** to RDS security group.

Verify (fill `repo root `.env``; tunnel Terminal 1 must stay open):

```powershell
node scripts/db/db_connectivity_smoke.js --env=production --mode=postgres
node scripts/db/rds_readiness_probe.js --target=production --confirm=<PROD_RDS_HOST>
```

---

## 2b. Manual RDS settings (console / Terraform)

Confirm before production traffic:

| Setting | Recommendation |
|---------|----------------|
| Engine | PostgreSQL **15.x** |
| Storage encryption | On |
| Automated backups | On; retention per policy (e.g. 7–35 days) |
| PITR | Enabled |
| Deletion protection | On before cutover |
| Multi-AZ | Per availability policy |
| `rds.force_ssl` | **1** in parameter group |
| CloudWatch alarms | CPU, free storage, `DatabaseConnections` |
| Public access | **Off** (use SSM tunnel for operators) |

## 3. Bootstrap empty RDS (production greenfield)

Create database (once, as master, via tunnel):

```sql
CREATE DATABASE doctornect ENCODING 'UTF8';
```

**Dry-run bootstrap list:**

```powershell
node scripts/db/rds_bootstrap_apply.js --target=production --confirm=<PROD_RDS_HOST>
```

**Execute** only after operator approval:

```powershell
node scripts/db/rds_bootstrap_apply.js --target=production --execute --confirm-live-data --confirm=<PROD_RDS_HOST>
```

## 3b. Bootstrap empty RDS (rehearsal first)

Connect as master to `doctornect_rehearsal`:

```powershell
cd c:\Users\khije\Downloads\DoctorNect\doctor
$env:REPLAY_DB_URL="postgresql://postgres:****@127.0.0.1:15432/postgres"

psql $env:REPLAY_DB_URL -f db/rds_bootstrap/01_roles_and_extensions.sql
psql $env:REPLAY_DB_URL -c "CREATE DATABASE doctornect_rehearsal ENCODING 'UTF8';"

# Session DB URL for rehearsal:
$env:REPLAY_DB_URL="postgresql://postgres:****@127.0.0.1:15432/doctornect_rehearsal"
psql $env:REPLAY_DB_URL -f db/rds_bootstrap/02_auth_shim.sql
psql $env:REPLAY_DB_URL -f db/rds_bootstrap/03_legacy_compat.sql
```

---

## 4. Apply migrations (guarded)

**Dry-run statements on rehearsal** (from network that can reach RDS):

```powershell
node scripts/db/migrate.js --target=production --dry-run-all --confirm-live-data --confirm=<PROD_RDS_HOST>
```

**Execute on production** (operator approval only):

```powershell
node scripts/db/migrate.js --target=production --execute --confirm-live-data --confirm=<PROD_RDS_HOST>
```

**Rehearsal** (optional second DB):

```powershell
node scripts/db/migrate.js --target=rehearsal --dry-run-all --confirm-live-data --confirm=<PROD_RDS_HOST>
```

**Execute on rehearsal:**

```powershell
node scripts/db/migrate.js --target=rehearsal --execute --confirm-live-data --confirm-staging
```

**Apply runtime grants** (least privilege for PostgREST roles):

```powershell
psql "<rehearsal-url>" -f db/rds_bootstrap/04_rds_runtime_grants.sql
```

---

## 5. Parity vs staging (operator-approved staging read)

Only after you approve staging access:

```powershell
node scripts/db/schema_diff.js --target=rehearsal
node scripts/db/grant_matrix_audit.js --compare-staging --confirm-live-data
node scripts/db/rls_sql_harness.js --target=rehearsal
```

Without staging: use cached report `docs/reports/fresh_local_vs_staging_schema_diff.json` and local rehearsal catalog.

---

## 6. PostgREST + Gateway on rehearsal

1. Deploy PostgREST 12.2.3 with `PGRST_DB_URI` → RDS (role `authenticator`).
2. Set `PGRST_JWT_SECRET`, `jwt-aud=authenticated` (match gateway).
3. Deploy API Gateway with `PGRST_URL`, `SERVICE_ROLE_KEY`, Firebase JWKS, `FIREBASE_REVOCATION_CHECK=true`.
4. Smoke from inside VPC:

```powershell
curl -s https://<gateway>/healthz
curl -s -H "apikey: <SERVICE_ROLE_KEY>" "https://<gateway>/rest/v1/notification_outbox?limit=0"
```

Local rehearsal of HTTP path:

```powershell
node scripts/db/real_path_authorization_e2e.js
```

---

## 7. Production cutover (ordered)

1. **Freeze** writes: maintenance window; disable user-facing signup if needed.
2. **Final staging snapshot** (Supabase backup / `pg_dump` — operator).
3. **Optional data sync** (if not greenfield): logical replication or one-time dump/load — project-specific (not automated in repo).
4. Run **§3–4** on `doctornect` production database.
5. Run **§5** `schema_diff --target=production` (with approval).
6. Point **PostgREST** and **Gateway** env to production RDS.
7. Update Flutter `PROD_GATEWAY_URL` / release build (`frontend/scripts/release_build.ps1`).
8. Set Cloud Functions `APP_ENV=production`, RDS-backed Supabase URL + **service role key** (Secrets Manager).
9. Run `backend/functions` + `api-gateway` test suites; prod smoke checklist in `docs/runbooks/PRODUCTION_CUTOVER_RDS.md`.

---

## 8. Rollback plan

| Step | Action |
|------|--------|
| 1 | Revert Gateway/PostgREST env to **Supabase** URLs (last known good revision). |
| 2 | Revert Flutter client to staging Supabase URL if already released. |
| 3 | Set `APP_ENV=staging` on functions if needed for dual-read period. |
| 4 | Keep RDS instance **running** but isolated (no traffic) until parity re-verified. |
| 5 | Do **not** drop RDS or truncate without second backup verification. |

---

## 9. Grant matrix (local automation)

```powershell
node scripts/db/generate_rds_runtime_grants.js
node scripts/db/grant_matrix_audit.js
# Optional live staging compare (ask operator first):
node scripts/db/grant_matrix_audit.js --compare-staging --confirm-live-data
```

Outputs: `docs/reports/grant_matrix_local.json`, `db/rds_bootstrap/04_rds_runtime_grants.sql`.

---

## 10. Related runbooks

- [RDS_MIGRATION_RUNBOOK.md](./RDS_MIGRATION_RUNBOOK.md) — migration flags, ledger quirks
- [PRODUCTION_CUTOVER_RDS.md](./PRODUCTION_CUTOVER_RDS.md) — broader cutover context
- [RDS_AUTHORIZATION.md](../db/RDS_AUTHORIZATION.md) — JWT + RLS model
