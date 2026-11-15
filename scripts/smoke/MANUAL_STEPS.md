# Staging / RDS smoke — manual steps (operator)

## Staging — admin bypass exposure + fix

**Read-only audit:**

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor
node scripts/db/staging_migration_exposure_audit.js
```

**Evidence:** `docs/audit/staging_migration_exposure_audit.txt`

**If `20261115000001` not in ledger** (even if function body already hardened):

```powershell
node scripts/db/apply_super_admin_hardening_staging.js
# then, with live-data guard:
node scripts/db/apply_super_admin_hardening_staging.js --confirm-live-data --execute
```

**Or single migration via `migrate.js`:**

```powershell
node scripts/db/migrate.js --target staging --dry-run
node scripts/db/migrate.js --target staging --confirm-live-data --execute
```

**Read-only sanity SQL (SQL editor):**

```sql
SELECT version, name, applied_at FROM public._schema_migrations
WHERE version IN ('20261112000003','20261115000001','20261115000002','20261115000003')
ORDER BY version;
SELECT count(*)::int AS admin_users_n FROM private.admin_users;
SELECT user_id, granted_at FROM private.admin_users ORDER BY granted_at DESC LIMIT 10;
SELECT pg_get_functiondef(p.oid) LIKE '%admin@doctornect.com%'
  AND pg_get_functiondef(p.oid) NOT LIKE '%private.admin_users%' AS email_only_bypass
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='private' AND p.proname='is_super_admin';
```

Expected: `email_only_bypass = false`; admin_users count small and known.

---

## RDS / Postgres — extensions probe (run on target instance)

```sql
SELECT name, default_version, installed_version, comment
FROM pg_available_extensions
WHERE name IN ('pgcrypto', 'uuid-ossp', 'pg_stat_statements', 'pg_cron', 'plpgsql')
ORDER BY name;

SELECT e.extname, n.nspname AS schema
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
WHERE e.extname IN ('pgcrypto', 'uuid-ossp')
ORDER BY e.extname;
```

Staging needs `pgcrypto` in `extensions` or `public`; migration `20261115000002_*` sets `enqueue_notification_outbox` `search_path` to `public, extensions, pg_temp`.

---

## Local replay (PG `:5440`)

```powershell
$env:REPLAY_DB_URL='postgresql://postgres:test@127.0.0.1:5440/postgres'
node scripts/db/rds_scratch_replay.js --confirm-live-data --execute --keep-db
```

Expected: `62 migrations, 1546+ statements, 0 failures` — `docs/audit/rds_scratch_replay_5440_rerun.txt`

```powershell
$env:LOCAL_FRESH_DB_URL='postgresql://postgres:test@127.0.0.1:5440/replay_check'
node scripts/smoke/staging_e2e_write_flow.js --target local
node scripts/db/concurrent_slot_booking_race.js
```

---

## OTP Redis integration (docker)

```powershell
docker run -d --name doctornect-otp-redis -p 6390:6379 redis:7
$env:REDIS_INTEGRATION_URL='redis://127.0.0.1:6390'
$env:FORCE_REDIS_INTEGRATION='1'
cd backend\functions
node --require ./test/setup_env.js --test test/otp_redis_integration.test.js
```

Evidence: `docs/audit/otp_redis_integration_only_6390.txt` (send/verify/cooldown; lockout step may need follow-up).

---

## Release AAB (staging-permitted artifact)

```powershell
cd frontend
.\scripts\release_build.ps1 -SkipIncrement -AllowStaging
```

**Proof:** `docs/audit/release_build_aab_proof.txt` (size ~98MB), build log `docs/audit/release_build_real_aab_log.txt` includes `--dart-define=FIRESTORE_FORBIDDEN=***`.

**Production Play track:** re-run **without** `-AllowStaging`, `APP_ENV=production`, gateway URL defines only.

```powershell
cd frontend
Remove-Item Env:STAGING_SUPABASE_URL -ErrorAction SilentlyContinue
$env:APP_ENV = 'production'
$env:PROD_GATEWAY_URL = '<your Auth Gateway base URL>'
# Must NOT load *.supabase.co into SUPABASE_URL for productionRelease gate:
$env:SUPABASE_URL = $env:PROD_GATEWAY_URL
$env:ENABLE_SUPABASE = '0'   # or '1' with SUPABASE_ANON_KEY + gateway URL only
.\scripts\release_build.ps1 -SkipIncrement
.\scripts\verify_aab_no_supabase_staging.ps1
```

If `flutter build` fails: confirm Android upload keystore (`android/key.properties` + `upload-keystore.jks`) and `FIREBASE_API_KEY_ANDROID` in repo root `.env` (never commit secrets).

Optional kernel check:

```powershell
.\scripts\verify_aab_firestore_forbidden.ps1
```

---

## Production RDS cutover (YOU run — no agent writes)

### 1. Backup

```bash
pg_dump "postgresql://USER@HOST:5432/doctornect?sslmode=verify-full" \
  --format=custom --file="doctornect_pre_cutover_$(date -u +%Y%m%dT%H%M%SZ).dump"
```

### 2. Version + extensions

```sql
SELECT version();
SELECT name, installed_version FROM pg_available_extensions WHERE name IN ('pgcrypto','uuid-ossp') ORDER BY 1;
```

### 3. Migrations

```bash
export APP_ENV=production
node scripts/db/migrate.js --target production --dry-run
node scripts/db/migrate.js --target production --confirm-live-data --execute
```

### 4. Post-migrate parity

```sql
SELECT count(*)::int AS migrations FROM public._schema_migrations;
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' ORDER BY tablename;
```

```bash
node scripts/db/schema_diff.js --target production   # when configured
```

### 5. RLS suite on RDS scratch / snapshot clone (not prod writes)

```bash
export LOCAL_FRESH_DB_URL="postgresql://USER@RDS_SCRATCH:5432/doctornect"
node scripts/db/gateway_rls_authorization_suite.js | tee docs/audit/gateway_rls_rds_scratch.txt
```

### 6. Gateway health

```bash
curl -fsS "https://<PROD_GATEWAY_HOST>/healthz"
node scripts/db/db_connectivity_smoke.js --target production
```