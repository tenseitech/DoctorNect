# Staging / RDS smoke — manual steps (operator)

> **Firestore is no longer used** (removed November 2026). Data lives in PostgreSQL: the five demo
> accounts in staging Supabase, every real user in AWS RDS behind the API gateway. Firebase is used
> only for Auth, App Check, Cloud Functions, Cloud Messaging and Remote Config. Anything below that
> mentions Firestore is historical. Current state: PROJECT_ANALYSIS.md, docs/GATEWAY_DEPLOY.md.

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

## Supabase demo project keepalive (free tier anti-pause)

**Repo visibility (GitHub Actions schedule):** `tenseitech/DoctorNect` is **public** (`"private": false` on GitHub API). On **public** repos, scheduled workflows **disable after 60 days with no default-branch activity** — treat **Firebase `supabaseKeepalive` as primary**; after long quiet periods, re-enable Actions under Settings → Actions → General, or make the repo private / use Supabase Pro. Confirm at GitHub → Settings → General → Danger Zone.

### (a) Firebase Secret Manager (deploy; values not in git)

```powershell
cd backend/functions
firebase functions:secrets:set DEMO_SUPABASE_URL
firebase functions:secrets:set DEMO_SUPABASE_SERVICE_ROLE_KEY
```

Use the **same** Supabase project URL and key as demo data-plane routing (`docs/DEMO_REAL_ROUTING.md`). Deploy exports `supabaseKeepalive` (schedule **03:30 Asia/Kolkata** daily).

### (b) GitHub backup workflow (removed 2026-11-26)

`.github/workflows/supabase-keepalive.yml` was deleted (PROJECT_ANALYSIS.md D6): the deployed
Functions `supabaseKeepalive` schedule does the same ping. Delete the repository secrets
`SUPABASE_KEEPALIVE_URL` and `SUPABASE_KEEPALIVE_KEY` (Settings > Secrets and variables > Actions);
nothing else reads them. If the key was a service-role key, rotate it in Supabase.

### (c) Cloud Monitoring alert

Log-based metric filter (Cloud Functions logs):

```
jsonPayload.event="supabase_keepalive_failed"
OR textPayload=~"supabase_keepalive_failed"
```

Alert policy → email on **any** match in 24h.

### (d) Supabase dashboard

Project → **Settings** → confirm status **Active** (not **Paused**). If paused → **Restore project**, then run keepalive once (`workflow_dispatch` or wait for schedule).

### (e) Verify keepalive is working

1. Firebase Console → Functions → `supabaseKeepalive` → Logs: look for `supabase_keepalive_ok` (INFO).
2. GitHub → Actions → **Supabase keepalive (backup)** → latest green run.
3. Supabase dashboard → **Database** → last activity / connection metrics (UNVERIFIED until live).

### (f) Paid plan decision

Stay on **free** while demo-only data + dual keepalive (Firebase + GitHub) is acceptable risk. Move to **Supabase Pro** before Play review window if you want SLA, no auto-pause, and no dependency on GitHub schedule rules.

---

## Demo → Supabase / Real → RDS (release gate)

**Design:** `docs/DEMO_REAL_ROUTING.md`

### Demo UID discovery (no UID/phone values in chat or logs)

1. **Firebase Console** → Authentication → Users → filter demo/test accounts → copy **UID** into password manager (do not paste into tickets).
2. **Or** after one successful reviewer login: Cloud Logging → filter callable `verifyUserRegistrationOtp` / `completeMobileOtpLogin` → field `uid_hash` / structured `firebaseUid` only in restricted logs; prefer Console UID export.
3. **Staging only:** `node scripts/audit/staging_non_demo_user_counts.js` counts non-allowlist phones (read-only); it does **not** read `system_config.demo_accounts`.

**Code does not use `system_config.demo_accounts` for routing** — `resolveDataPlane()` reads env only (`scripts/lib/demo_routing.js`). OTP demo/reviewer paths use `REVIEW_*_PHONES` (`registration_otp.js`). DB key `demo_accounts` is legacy schema seed + audit probe (`anon_surface_audit.js`); purge on RDS via `20261117000002` / `20261026000001`.

### Secrets (no literal values in repo)

**Firebase Functions (per secret):**

```powershell
firebase functions:secrets:set DEMO_FIREBASE_UID_ALLOWLIST --project <FIREBASE_PROJECT_ID>
firebase functions:secrets:set DEMO_SUPABASE_URL --project <FIREBASE_PROJECT_ID>
firebase functions:secrets:set DEMO_SUPABASE_SERVICE_ROLE_KEY --project <FIREBASE_PROJECT_ID>
firebase functions:secrets:set REVIEWER_OTP_ENABLED --project <FIREBASE_PROJECT_ID>
firebase functions:secrets:set REVIEW_FIXED_OTP --project <FIREBASE_PROJECT_ID>
firebase functions:secrets:set REVIEW_ACCESS_UNTIL --project <FIREBASE_PROJECT_ID>
# Per role: REVIEW_PATIENT_PHONES, REVIEW_DOCTOR_PHONES, ...
```

Bind in function definitions / `firebase.json` secret refs; redeploy affected functions.

**ECS API gateway (AWS Secrets Manager)** — store JSON or separate keys, then map in task definition env:

```powershell
aws secretsmanager create-secret --name doctornect/demo-routing --secret-string file://-( <<< '{"DEMO_REAL_ROUTING_ENABLED":"1","DEMO_PGRST_URL":"...","DEMO_PGRST_JWT_SECRET":"..."}')
```

Rotate `DEMO_PGRST_JWT_SECRET` to match demo Supabase JWT secret; never commit `.env`.

### Before applying `20261117000002` on staging

1. Grep confirmed: no app reads `demo_accounts` from Postgres (routing/OTP use env). Staging Supabase may still rely on `promoted_ads` / `patient_module_status` keys — migration **deletes only** `demo_accounts` and inserts public keys idempotently.
2. Run `node scripts/db/anon_surface_audit.js --target=staging --confirm-live-data` (expect `demo_accounts` absent after apply).

1. **Supabase (demo plane)** — keep staging project on a paid plan or scheduled keepalive (`node scripts/db/staging_health_ping.js` if configured). Store **only** demo/reviewer data.
2. **Secrets (gateway ECS / Functions)** — set server-side only (never Flutter):
   - `DEMO_REAL_ROUTING_ENABLED=1`
   - `DEMO_FIREBASE_UID_ALLOWLIST` — comma Firebase UIDs for App Store / Play demo logins
   - `DEMO_PGRST_URL` + `DEMO_PGRST_JWT_SECRET` — Supabase PostgREST base + JWT secret (same as Supabase project JWT secret)
   - `DEMO_SUPABASE_URL` + `DEMO_SUPABASE_SERVICE_ROLE_KEY` — Functions demo plane
   - Keep `PROD_GATEWAY_URL` as the **only** URL in the release app.
3. **Reviewer OTP** — `REVIEWER_OTP_ENABLED=true`, `REVIEW_*_PHONES`, `REVIEW_FIXED_OTP`, `REVIEW_ACCESS_UNTIL`; dedicated **99999xxxxx** numbers only; rotate before store review ends.
4. **Allowlist maintenance** — after creating demo Firebase users, append UID to `DEMO_FIREBASE_UID_ALLOWLIST`; optional legacy prefix routing only if `DEMO_UID_PREFIX_ROUTING=1` (default off).
5. **Audit** — `node scripts/audit/staging_non_demo_user_counts.js` (read-only) before cutover.

Tests:

```powershell
node --test scripts/test/demo_routing.test.js
cd backend/functions; node --test test/demo_real_isolation.test.js test/db_client.test.js
cd services/api-gateway; npm test
```

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
$env:REPLAY_DB_URL='postgresql://rdsadmin:test@127.0.0.1:5442/doctornect'
$env:LOCAL_REPLAY_PG_PORT='5442'
$env:REPLAY_RDS_LIKE='1'
node scripts/db/rds_scratch_replay.js --target=replay --confirm-live-data --keep-db
$env:LOCAL_FRESH_DB_URL='postgresql://rdsadmin:test@127.0.0.1:5442/replay_check'
node scripts/db/gateway_rls_authorization_suite.js
node scripts/db/rds_role_grants_matrix.js --target=replay_check --confirm-live-data
```

`docs/audit/allowed_host_hashes.txt` must include **12CA17B4** (`127.0.0.1`) and/or use hostname `localhost` (**49960DE5**).

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

## Production RDS — full greenfield sequence (reset → bootstrap → migrate)

Use when catalog is empty or after failed migrate + operator reset. **`DROP SCHEMA public CASCADE` removes `public._schema_migrations`** (ledger cleared).

### Failed migrate recovery

1. Fix root error (e.g. missing bootstrap → run pre-migrate 01–03 before migrate).
2. New RDS snapshot / note snapshot id.
3. If non-empty residue blocks reset: `prod_rds_reset_empty.js` with `--allow-seed-system-config` only when `system_config` holds schema seed keys only (`demo_accounts`, `promoted_ads`).
4. Re-run **PROD SEQUENCE** below from step 2 (bootstrap pre). Do not `--execute` migrate until bootstrap OK.

### PROD SEQUENCE (PowerShell)

```powershell
$h = ((Select-String -Path .env -Pattern '^PROD_RDS_HOST=').Line -split '=', 2)[1].Trim()
$db = ((Select-String -Path .env -Pattern '^PROD_RDS_DB=').Line -split '=', 2)[1].Trim()
if (-not $db) { $db = 'doctornect' }

# 1 Reset (after empty-table / seed-only gate)
$resetArgs = @(
  'scripts/db/prod_rds_reset_empty.js', '--execute',
  "--confirm-host=$h", "--confirm-db=$db", '--i-took-snapshot=<SNAPSHOT_ID>',
  '--allow-seed-system-config'
)
node @resetArgs

# 2 Bootstrap pre-migrate (01–03: roles, auth shim, auth.users stub)
$bootPreArgs = @(
  'scripts/db/rds_bootstrap_apply.js', '--target=production', '--execute', '--pre-migrate-only',
  '--confirm-live-data', "--confirm=$h", "--confirm-db=$db"
)
node @bootPreArgs

# 3 Migrate (71 files)
$migArgs = @(
  'scripts/db/migrate.js', '--target=production', '--execute',
  '--confirm-live-data', "--confirm=$h", "--confirm-db=$db"
)
node @migArgs

# 4 Bootstrap post-migrate (04 runtime grants)
$bootPostArgs = @(
  'scripts/db/rds_bootstrap_apply.js', '--target=production', '--execute',
  '--confirm-live-data', "--confirm=$h", "--confirm-db=$db"
)
node @bootPostArgs

# 5 Read-only verify (no DDL/DML)
node scripts/db/prod_rds_readonly_diagnostic.js
```

**Local rdslike rehearsal (same scripts/role, not rdsadmin):** set `PROD_RDS_CONNECT_HOST=127.0.0.1`, `PROD_RDS_PORT=5442`, `PROD_RDS_USER=doctornect_admin`, `PROD_RDS_SSLMODE=require`, `PROD_RDS_HOST=127.0.0.1`, `PROD_RDS_DB=doctornect_rehearsal`; use `--target=rehearsal` and `--confirm-db=doctornect_rehearsal` in bootstrap/migrate args (same `$h` pattern). Add `--allow-no-cron` on migrate **only** if local engine lacks `pg_cron` (production RDS must **not** use that flag).

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