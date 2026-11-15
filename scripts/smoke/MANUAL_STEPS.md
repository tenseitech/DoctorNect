# Staging / RDS smoke — manual steps (operator)

## Cutover order (numbered)

1. **IAM** — RDS/SG read permissions (or console checks)
2. **Tunnel + preflight** — SSM tunnel `127.0.0.1:5433` → RDS; `node scripts/db/prod_rds_preflight_readonly.js` (stop if unexpected tables/data)
3. **Backup** — `pg_dump` via tunnel (see Production RDS cutover)
4. **Migrate** — `migrate.js --target=production` with confirm flags
5. **Parity** — SQL counts (ledger, RLS, policies); optional `schema_diff.js` when staging+prod reachable
6. **Gateway deploy** — Terraform/image (see Gateway deploy status) — **UNVERIFIED** if already live
7. **Functions** — secrets/env + `firebase deploy --only functions` (your approval)
8. **AAB** — production `release_build.ps1` + verify scripts
9. **Phone test** — real OTP on staging/prod

---

## ECS GATEWAY + DEPLOY RUNBOOK (ordered — no agent apply)

Reference: `docs/audit/TERRAFORM_RESOURCE_AUDIT.md`, `infra/aws/terraform.tfvars.example`, `scripts/deploy/ecr_push_gateway.ps1`, `scripts/deploy/set_secrets.ps1`.

| Step | Action | Pass criterion |
|------|--------|----------------|
| 1 | **ECR** — `.\scripts\deploy\ecr_push_gateway.ps1 -AwsAccountId <ACCOUNT>` | Image URI matches `gateway_image` in tfvars |
| 2 | **PostgREST pin** — ECS uses `postgrest/postgrest:v16.5` (`variables.tf` default) | Task definition env: `PGRST_DB_SCHEMAS=public`, `PGRST_DB_ANON_ROLE=anon` |
| 3 | **Terraform tfvars** — copy `terraform.tfvars.example` → `terraform.tfvars` (gitignore) | Existing VPC/subnets/RDS SG IDs only — no new RDS |
| 4 | **terraform validate / plan** — `cd infra/aws && terraform init && terraform plan` | **0** `aws_db_instance` create/destroy; RDS changes only optional **parameter group attach** (manual CLI in `rds.tf` comments) |
| 5 | **terraform apply** | ALB DNS output; WAF associated (`waf.tf`); ECS tasks **UNVERIFIED** until you confirm |
| 6 | **Secrets Manager values** (after apply creates empty secrets) | JSON for `connection_string`, `jwt_secret`, `service_key` — see audit doc (`openssl rand -hex 32`) |
| 7 | **RDS bootstrap** | Roles `authenticator` / `anon` / `authenticated` / `service_role` via `db/rds_bootstrap/01_roles_and_extensions.sql` (+ grants `04_rds_runtime_grants.sql`); migrate production |
| 8 | **Health** — `curl -fsS https://<api-host>/healthz` | 200 + PostgREST upstream healthy |
| 9 | **`node scripts/db/db_connectivity_smoke.js --env=production`** | Gateway reads OK (**UNVERIFIED** until live) |
| 10 | **Firebase** — `firebase login --reauth`; `firebase use <prod>` | `firebase projects:list` succeeds |
| 11 | **Root `.env` production keys** (not committed) — `APP_ENV=production`, `FIRESTORE_FORBIDDEN=1`, `PROD_GATEWAY_URL=https://<api-host>`, `ENABLE_SUPABASE_SYNC=0`, plus MSG91/Redis/Razorpay per `.env.example` | `node scripts/env/build_env_example_from_templates.js` parity optional |
| 12 | **`.\scripts\deploy\set_secrets.ps1`** | Prompted secrets only; no values in repo |
| 13 | **`firebase deploy --only functions`** (your GO) | Predeploy runs `materialize_functions_env.js` from root `.env` |
| 14 | **AAB** — `frontend\scripts\release_build.ps1` (production defines) | Pre-release scripts pass |

**Firebase auth (2026-11-15):** `firebase login:list` shows account; **`firebase projects:list` failed** — run **`firebase login --reauth`** before step 10.

---

## MANUAL STEPS FOR ME (agent cannot complete)

| # | Task | Why manual |
|---|------|------------|
| 1 | **AWS IAM** — grant `doctornect-admin` `rds:DescribeDBInstances`, `rds:DescribeDBParameters`, `ec2:DescribeSecurityGroups` (or run checks in console) | CLI: `AccessDenied` — `docs/audit/aws_rds_cli_access_denied.txt` |
| 2 | **RDS SSM tunnel** — start tunnel so `127.0.0.1:5433` → prod RDS (`docs/runbooks/RDS_PROD_TUNNEL_WINDOWS.md`) | Preflight: `ECONNREFUSED 127.0.0.1:5433` — `docs/audit/prod_rds_preflight_readonly.txt` |
| 3 | **Production RDS migrate** — after tunnel: preflight → backup → migrate with `--confirm=<PROD_RDS_HOST> --confirm-db=doctornect` | Agent stopped: no tunnel + live-data guard |
| 4 | **Firebase login** — `firebase login --reauth` | `firebase projects:list` failed |
| 5 | **Functions secrets/params** — see **Firebase production env** (values only you set) | No secret values in chat/logs |
| 6 | **`firebase deploy --only functions`** | Only after you approve env + smoke |
| 7 | **Production AAB** — `APP_ENV=production`, gateway URL defines, keystore | `release_build_prod_skipinc.txt` |
| 8 | **Prod gateway `/healthz`** | From network that reaches ALB/ECS |
| 9 | **Real OTP + phone** | MSG91 + device |
| 10 | **Slot capacity** — **1** vs **3** per slot | `MIGRATION_STATUS.md` OPEN QUESTIONS |
| 11 | **RDS safe toggles** — backup retention / deletion protection via CLI | IAM + confirm before `modify-db-instance` |

---

## AWS RDS checks (operator console or IAM-fixed CLI)

```powershell
# After IAM fix:
aws rds describe-db-instances --query "DBInstances[*].[DBInstanceIdentifier,EngineVersion,PubliclyAccessible,StorageEncrypted,BackupRetentionPeriod,DeletionProtection,MultiAZ]" --output table

aws rds describe-db-parameters --db-parameter-group-name <PG_NAME> --query "Parameters[?ParameterName=='rds.force_ssl']"

aws ec2 describe-security-groups --group-ids <RDS_SG_ID> --query "SecurityGroups[0].IpPermissions[?ToPort==\`5432\`]"
```

**Gaps (repo + assumed risks):** `docs/audit/infra_rds_security_gaps.txt` — verify `PubliclyAccessible=false`, no `0.0.0.0/0:5432`, `rds.force_ssl=1` **applied** (not only pending-reboot).

**Safe modify (confirm before running):**

```powershell
# aws rds modify-db-instance --db-instance-identifier <ID> --backup-retention-period 7 --apply-immediately
# aws rds modify-db-instance --db-instance-identifier <ID> --deletion-protection --apply-immediately
```

SQL on RDS (via tunnel):

```sql
SELECT name, installed_version FROM pg_available_extensions
WHERE name IN ('pgcrypto','plpgsql','uuid-ossp') ORDER BY 1;
```

---

## Functions → RDS connectivity (design — do not execute here)

**How `pg_pool` connects in production** (`backend/functions/src/db/pg_pool.js`):

| `APP_ENV` | URL source |
|-----------|------------|
| `staging` | `STAGING_SUPABASE_DB_URL` / `SUPABASE_DB_URL` / `DATABASE_URL` (Supabase pooler) |
| `production` | `DATABASE_URL` (must **not** contain `supabase.co`), **or** `PROD_RDS_*` via `scripts/lib/rds_pool_config.js` (TLS + `infra/aws/global-bundle.pem`) |

**Cloud Functions have no static egress IP** (Google-managed). Options to reach private RDS:

| Option | How it works | Repo readiness | Risk |
|--------|----------------|----------------|------|
| **A. Gateway only** | Client + callables use **PostgREST** (`PROD_GATEWAY_URL` / `getDatabaseClient()`); **no** direct `pg_pool` to RDS in hot paths | **Ready** — `src/db/client.js`, ECS PostgREST in `infra/aws/ecs.tf` | SQL-only jobs still need B or C |
| **B. VPC connector + NAT + SG allowlist** | Functions attach `VPC_CONNECTOR` (see `index.js`); egress via Cloud NAT with stable IP; RDS SG allows that IP | **Partial** — `VPC_CONNECTOR` env hook in `index.js`; **no** full VPC/NAT/SG→RDS wiring in `infra/aws/*.tf` for GCP | Ops complexity; must not open `0.0.0.0/0` |
| **C. RDS Proxy / public + TLS only** | `DATABASE_URL` to RDS endpoint (tunnel today; prod via TLS + narrow SG) | **Partial** — `rds.tf` params (`rds.force_ssl`); instance not fully codified | Mis-SG = exposure |

**Recommendation:** **A** for all app reads/writes through Auth Gateway; use **B** only for functions that **must** call `pg_pool` / raw SQL (DLQ, maintenance). Until VPC connector is provisioned, set production `DATABASE_URL` only for those jobs or run SQL via gateway RPC where possible.

**Production paths that still ask for direct RDS (`DATABASE_URL` / `PROD_RDS_*`) at runtime:**

| Count | Module | Notes |
|-------|--------|-------|
| **0** | Cloud Functions **exports** (`index.js`) | OTP, payments, delete account, workers → `getDatabaseClient()` only |
| **1** | `cross_role_sync.js` (batch; **not** exported) | DLQ + Firestore→PG sync; `needs pg_pool` — run only with RDS reachability or leave disabled (`ENABLE_SUPABASE_SYNC=0`) |

`assertProductionCutoverBoot` does **not** require `DATABASE_URL` for the default Functions deploy. First `getPgPool()` call in production still fails fast with `[pg_pool] APP_ENV=production requires …` if RDS env is missing.

Audit table: `docs/audit/PG_POOL_CALLER_AUDIT.md`.

---

## Gateway deploy status

**In repo (`infra/aws/ecs.tf`):**

- Fargate task: **auth-gateway** (:3000) + **PostgREST** (:3001) in one task; PostgREST uses `PGRST_DB_URI` from Secrets Manager.
- ALB listener → gateway; ECS in **private subnets**, `assign_public_ip = false`.
- Images: `var.gateway_image`, `var.postgrest_image` (ECR tags — not pinned in this snippet).

**Gateway hardening (code):** service key auth uses constant-time compare (`services/api-gateway/src/security.js`). Deny-by-default: unlisted tables/RPCs → **403 Forbidden** (`services/api-gateway/src/server.js`). Tests: `gateway.test.js`, `gateway_role_access.test.js`, `allowlist_completeness.test.js`.

**WAF (Terraform — apply only after operator review):**

- Template: `infra/aws/waf.tf` — `aws_wafv2_web_acl` (Common + KnownBadInputs + IP reputation + rate limits) + `aws_wafv2_web_acl_association` on `aws_lb.api`.
- Local check (no AWS creds required): `cd infra/aws && terraform init -backend=false && terraform validate`
- Apply (production): after `terraform plan` shows only intended WAF + association changes, `terraform apply` with production workspace/vars; verify WAF metrics in CloudWatch and spot-check `/healthz` + one authenticated `/rest/v1` call.

**Deploy flow (operator):**

1. Build/push gateway image (`services/api-gateway`) and pin PostgREST image to ECR.
2. `terraform apply` in `infra/aws` with correct `var.environment`, subnets, certs (include WAF when ready).
3. Confirm ALB DNS + ACM cert.

**Whether production gateway is already live:** **UNVERIFIED** (no Terraform state / AWS API access from agent).

**Before `/healthz` probe:**

- [ ] RDS migrated and reachable from PostgREST task SG
- [ ] Secrets Manager: DB URI, JWT secret, gateway service key populated
- [ ] ECS service `desired_count ≥ 1`, tasks healthy
- [ ] ALB target group healthy
- [ ] `PROD_GATEWAY_URL` in client `.env` matches ALB URL (not `*.supabase.co`)

```powershell
curl -fsS "https://<PROD_GATEWAY_HOST>/healthz"
node scripts/db/db_connectivity_smoke.js --env=production
```

---

## Firebase production env (names only — you set values)

Prerequisites: `firebase login --reauth`, `firebase use <prod-project>`.

**Cloud Functions runtime (minimum from `assertProductionCutoverBoot` + routing):**

- `APP_ENV` = `production`
- `FIRESTORE_FORBIDDEN` = `1`
- `PROD_GATEWAY_URL`, `PROD_GATEWAY_SERVICE_KEY` — PostgREST admin client (`backend/functions/src/db/client.js`)
- `DATABASE_URL` — **optional** for default Functions deploy; required only if you run `cross_role_sync` / direct `getPgPool()` jobs (RDS TLS URL; must not be Supabase host)
- `REDIS_*` (+ TLS for prod)
- `MSG91_AUTH_KEY`, template IDs, `OTP_HMAC_SECRET`, `RAZORPAY_*`, `S3_*`, `ENABLE_SUPABASE_SYNC=0`

**Production PostgREST key (grep proof — not Supabase cloud service role):**

```text
backend/functions/src/db/client.js       → production: PROD_GATEWAY_SERVICE_KEY
backend/functions/delete_my_account.js   → production branch: PROD_GATEWAY_SERVICE_KEY
backend/functions/src/db/assert_app_env.js → production: PROD_GATEWAY_SERVICE_KEY required
```

Some callables still **declare** `defineSecret('SUPABASE_SERVICE_ROLE_KEY')` in deploy metadata (`promoted_ads.js`, `s3_storage.js`, …) but **runtime** uses `getDatabaseClient()` → **PROD_GATEWAY_SERVICE_KEY** when `APP_ENV=production`. Do **not** put a Supabase `service_role` JWT in production Firebase for cutover. Until code removes unused `defineSecret`, you may bind the same gateway service key value to satisfy deploy, or refactor secrets on those exports (post-release).

**Set secrets (values at prompt — never commit):**

```powershell
cd backend\functions
firebase functions:secrets:set DATABASE_URL
firebase functions:secrets:set PROD_GATEWAY_SERVICE_KEY
firebase functions:secrets:set MSG91_AUTH_KEY
firebase functions:secrets:set RAZORPAY_KEY_SECRET
firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET
firebase functions:secrets:set OTP_HMAC_SECRET
# REDIS_*, AWS_*, etc. per defineSecret in index.js / redis.js / s3_storage.js
```

Set **non-secret** env in Firebase console: `APP_ENV`, `FIRESTORE_FORBIDDEN`, `PROD_GATEWAY_URL`, `VPC_CONNECTOR` (if used), `ENABLE_SUPABASE_SYNC=0`.

**Boot guard unit proof:** `docs/audit/assert_production_cutover_boot_test.txt`.

---

## Staging — admin bypass exposure + fix

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor
node scripts/db/staging_migration_exposure_audit.js
```

**Or migrate (staging):**

```powershell
node scripts/db/migrate.js --target=staging --dry-run-all --confirm-live-data
node scripts/db/migrate.js --target=staging --confirm-live-data --execute
```

---

## RDS / Postgres — extensions probe

```sql
SELECT name, default_version, installed_version, comment
FROM pg_available_extensions
WHERE name IN ('pgcrypto', 'uuid-ossp', 'pg_stat_statements', 'pg_cron', 'plpgsql')
ORDER BY name;
```

---

## AWS RDS `pg_cron` (production parameter group)

1. RDS console → **Parameter group** for the instance (or create `doctornect-pg18-custom`).
2. Set `shared_preload_libraries` to include **`pg_cron`** (keep existing entries such as `pg_stat_statements`, `rdsutils` — comma-separated).
3. Set `cron.database_name` = **`doctornect`** (must match `PROD_RDS_DB`).
4. **Reboot** the RDS instance (pending-reboot parameters).
5. As `doctornect_admin`: `CREATE EXTENSION IF NOT EXISTS pg_cron;` (migration `20260923000003_doctornect_cron.sql` does this when preload is enabled).
6. Without preload, `migrate.js` **fails closed** with `PG_CRON_NOT_AVAILABLE` — emergency only: `--allow-no-cron` (skips cron migration; use an external scheduler).

Read-only check:

```powershell
node scripts/db/prod_rds_readonly_diagnostic.js
```

## RDS-like local (Postgres 18, no `postgres` role)

```powershell
cd scripts/docker/rdslike-pg18
docker compose up -d
cd ../..
node scripts/db/rdslike_apply_bootstrap.js
$env:REPLAY_DB_URL='postgresql://doctornect_admin:test@localhost:5442/postgres'
$env:REPLAY_RDS_LIKE='1'
node scripts/db/migrate.js --target=replay --dry-run-all --allow-no-cron --confirm-live-data
node scripts/db/migrate.js --target=replay --execute --allow-no-cron --confirm-live-data
$env:LOCAL_FRESH_DB_URL='postgresql://doctornect_admin:test@localhost:5442/doctornect'
node scripts/db/gateway_rls_authorization_suite.js
```

Evidence: `docs/audit/prod_dry_run_all_post_fix2.txt`, `docs/audit/gateway_rls_rdslike_5442.txt`.

Production dry-run (rollback only, tunnel `127.0.0.1:5433`):

```powershell
node scripts/db/migrate.js --target=production --dry-run-all --allow-no-cron --confirm-live-data --confirm-db=doctornect --confirm=$env:PROD_RDS_HOST
```

## Local replay (PG `:5440`)

```powershell
$env:REPLAY_DB_URL='postgresql://postgres:test@127.0.0.1:5440/postgres'
node scripts/db/rds_scratch_replay.js --confirm-live-data --execute --keep-db
```

```powershell
$env:LOCAL_FRESH_DB_URL='postgresql://postgres:test@127.0.0.1:5440/replay_check'
node scripts/smoke/staging_e2e_write_flow.js --target local
node scripts/db/concurrent_slot_booking_race.js
```

Evidence: `docs/audit/staging_e2e_write_flow_local_5440.txt`

---

## OTP Redis integration (docker)

```powershell
docker run -d --name doctornect-otp-redis -p 6390:6379 redis:7
$env:REDIS_INTEGRATION_URL='redis://127.0.0.1:6390'
$env:FORCE_REDIS_INTEGRATION='1'
cd backend\functions
node --require ./test/setup_env.js --test test/otp_redis_integration.test.js
```

**Evidence:** `docs/audit/otp_redis_integration_only_6390.txt` — **PASS** (Lua lockout, 20 parallel wrong guesses, counter ≤ 5).

---

## Release AAB (staging-permitted artifact)

```powershell
cd frontend
.\scripts\release_build.ps1 -SkipIncrement -AllowStaging
```

**Production Play track** (client uses `supabase_flutter` → **Auth Gateway**, not Supabase cloud):

```powershell
cd frontend
Remove-Item Env:STAGING_SUPABASE_URL -ErrorAction SilentlyContinue
$env:APP_ENV = 'production'
$env:PROD_GATEWAY_URL = '<your Auth Gateway base URL>'
$env:SUPABASE_URL = $env:PROD_GATEWAY_URL
$env:ENABLE_SUPABASE = '1'
$env:SUPABASE_ANON_KEY = '<PROD_GATEWAY_ANON_KEY or published anon key>'
.\scripts\release_build.ps1 -SkipIncrement
.\scripts\verify_aab_no_supabase_staging.ps1
.\scripts\verify_aab_firestore_forbidden.ps1
```

Keystore: `android/key.properties` + `upload-keystore.jks`; `FIREBASE_API_KEY_ANDROID` in root `.env` (never commit).

---

## Production RDS cutover (YOU run — no agent writes)

### 1. Backup (via tunnel host `127.0.0.1:5433`)

```powershell
# Prefer sslmode=require through tunnel; optional CA:
# sslmode=verify-ca&sslrootcert=infra/aws/global-bundle.pem
pg_dump "postgresql://USER:PASSWORD@127.0.0.1:5433/doctornect?sslmode=require" `
  --format=custom --file="doctornect_pre_cutover_$(Get-Date -Format yyyyMMddTHHmmss)Z.dump"
```

Do **not** commit dump files.

### 2. Version + extensions

```sql
SELECT version();
SELECT name, installed_version FROM pg_available_extensions WHERE name IN ('pgcrypto','uuid-ossp') ORDER BY 1;
```

### 3. Migrations

```powershell
$env:APP_ENV = 'production'
node scripts/db/migrate.js --target=production --dry-run-all --confirm-live-data --confirm=<PROD_RDS_HOST> --confirm-db=doctornect
node scripts/db/migrate.js --target=production --execute --confirm-live-data --confirm=<PROD_RDS_HOST> --confirm-db=doctornect
```

Replace `<PROD_RDS_HOST>` with the **hostname** from `.env` (`PROD_RDS_HOST`, not the tunnel IP). If migrate aborts, **do not retry blindly** — inspect error and ledger.

### 4. Post-migrate parity

**Primary (SQL on RDS via tunnel):**

```sql
SELECT count(*)::int AS migration_count FROM public._schema_migrations;
SELECT count(*)::int AS tables_public FROM pg_tables WHERE schemaname = 'public';
SELECT count(*)::int AS rls_on FROM pg_tables WHERE schemaname = 'public' AND rowsecurity = true;
SELECT count(*)::int AS policies_public FROM pg_policies WHERE schemaname = 'public';
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
```

Compare `migration_count` to repo file count under `db/migrations` (+ `db/rds_overrides` applied set). Baseline from local replay: `docs/audit/rds_scratch_replay_5440_rerun.txt`.

**Optional (tool exists):** `scripts/db/schema_diff.js` — compares staging vs production catalogs when both URLs are configured (`node scripts/db/schema_diff.js --help`). Not required if SQL parity above matches local replay.

### 5. RLS suite on RDS snapshot clone (not prod writes)

```powershell
$env:LOCAL_FRESH_DB_URL="postgresql://USER@RDS_SCRATCH:5432/doctornect"
node scripts/db/gateway_rls_authorization_suite.js | Tee-Object docs/audit/gateway_rls_rds_scratch.txt
```

### 6. Gateway health

See **Gateway deploy status** above.