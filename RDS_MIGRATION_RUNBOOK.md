# RDS Migration Runbook (Staging Supabase → Production RDS)

**Audience:** Operator / DBA  
**Code reference:** `scripts/db/migrate.js`, `db/rds_bootstrap/`, `scripts/db/rds_scratch_replay.js`  
**Safety:** Do not run destructive commands against production without backup. This document is dry-run first.

---

## 1. Prerequisites

| Item | Evidence in repo |
|---|---|
| PostgreSQL 17 client (`psql`, `pg_dump`) on operator workstation | `docs/runbooks/PRODUCTION_CUTOVER_RDS.md` |
| RDS instance `available`, engine `postgres` 17.x | `infra/aws/rds.tf` |
| Parameter group with `pg_cron` | `doctornect-production-pg17-cron` |
| SSL CA bundle | `infra/aws/global-bundle.pem` |
| Env file (not committed) | `STAGING_SUPABASE_DB_URL`, `REPLAY_DB_URL` or prod RDS URL |

---

## 2. Staging (Supabase) — apply pending migrations

**Connection:** set `STAGING_SUPABASE_DB_URL` to the **session pooler (port 5432)** or direct database host. The transaction pooler (`:6543`) aborts multi-statement transactions used by migrate/harness/audit scripts.

```powershell
cd c:\Users\khije\Downloads\DoctorNect\doctor
# Dry-run all pending statements
node scripts/db/migrate.js --target=staging --dry-run-all
# Apply (requires STAGING_SUPABASE_DB_URL in environment / .env.migration)
node scripts/db/migrate.js --target=staging
```

Verify:

```powershell
node scripts/db/rls_sql_harness.js --target=staging
```

Expected (verified **2026-10-31** live staging run): **208 PASS / 0 FAIL** — report `docs/reports/rls_harness_staging_2026-10-31T07-00-11-064Z.md` (command: `node scripts/db/rls_sql_harness.js --target=staging`).

---

## 3. RDS bootstrap (empty instance)

Connect as master user and run **in order**:

1. `db/rds_bootstrap/01_roles_and_extensions.sql` — roles, extensions, `pg_cron`
2. `db/rds_bootstrap/02_auth_shim.sql` — `auth.jwt()`, `auth.uid()` Firebase-compatible shims
3. `db/rds_bootstrap/03_legacy_compat.sql` — Supabase-compat helpers for plain RDS

```bash
psql "$PROD_RDS_ADMIN_URL" -f db/rds_bootstrap/01_roles_and_extensions.sql
psql "$PROD_RDS_ADMIN_URL" -f db/rds_bootstrap/02_auth_shim.sql
psql "$PROD_RDS_ADMIN_URL" -f db/rds_bootstrap/03_legacy_compat.sql
```

---

## 4. Authorization on RDS (no Supabase Auth for clients)

See **`docs/db/RDS_AUTHORIZATION.md`**: Firebase-only identity, gateway-minted PostgREST JWTs, single backend DB user, RLS via `auth.jwt()` shim. Migrations guard `anon`/`authenticated` grants when roles are missing.

After migration **`20261103000008_staging_anon_security_cleanup.sql`**, verify anonymous surface:

Use **`STAGING_SUPABASE_DB_URL` on session pooler port 5432** (not transaction pooler 6543) for `migrate.js`, `rls_sql_harness.js`, and `anon_surface_audit.js`.

```powershell
node scripts/db/anon_surface_audit.js --target=staging
```

---

## 5. Migration order (46 files — identical on Supabase and RDS)

Apply via `node scripts/db/migrate.js --target=production` once `PROD_RDS_*` / connection URL is wired in `scripts/lib/env_loader.js`, **or** replay locally:

| # | File |
|---|------|
| 1 | `20260923000001_doctornect_schema.sql` |
| 2 | `20260923000002_doctornect_rls.sql` |
| 3 | `20260923000003_doctornect_cron.sql` |
| 4 | `20260925000001_sync_bridge_infra.sql` |
| 5 | `20260926000001_atomic_appointment_booking.sql` |
| 6 | `20260928000001_add_health_records_s3_storage_fields.sql` |
| 7 | `20260928000002_add_lab_reports_s3_storage_fields.sql` |
| 8 | `20260928000003_add_profile_photos_s3_storage_fields.sql` |
| 9 | `20260929000001_add_promoted_ads_s3_storage_fields.sql` |
| 10 | `20260930000001_fix_security_advisor_warnings.sql` |
| 11 | `20260930000002_admin_users_table.sql` |
| 12 | `20260930000003_users_integrity.sql` |
| 13 | `20260930000004_access_gap_fixes.sql` |
| 14 | `20260930000005_users_provisioning.sql` |
| 15 | `20260930000006_column_locks.sql` |
| 16 | `20260930000007_auth_user_lookup.sql` |
| 17 | `20261001000001_bind_otp_challenges.sql` |
| 18 | `20261001000002_harden_auth_provisioning.sql` |
| 19 | `20261002000001_is_super_admin_null_safe.sql` |
| 20 | `20261008000001_firebase_uid_identity.sql` |
| 21 | `20261008000002_super_admin_from_admin_users.sql` |
| 22 | `20261008000003_allow_firebase_users_drop_fkey.sql` |
| 23 | `20261020000001_consolidated_firebase_schema_and_rls.sql` |
| 24 | `20261020000002_phase_c_doctor_patient_cutover.sql` |
| 25 | `20261021000001_sensitive_data_isolation.sql` |
| 26 | `20261021000002_phase_d_pharmacy_lab_ambulance.sql` |
| 27 | `20261021000003_phase_e1_auth_and_super_admins.sql` |
| 28 | `20261021000004_phase_e2_support_and_notifications.sql` |
| 29 | `20261021000005_phase_e3_razorpay_and_promoted_ads.sql` |
| 30 | `20261021000006_db_hardening.sql` |
| 31 | `20261022000001_phase_f_complete_cutover.sql` |
| 32 | `20261025000001_least_privilege_grants_and_rls.sql` |
| 33 | `20261026000001_rpc_null_safe_authz.sql` |
| 34 | `20261029000001_guard_and_drift_fixes.sql` |
| 35 | `20261030000001_domain_security_and_client_guards.sql` |
| 36 | `20261031000001_trusted_writers_and_domain_fixes.sql` |
| 37 | `20261101000001_domain_allowlist_and_reviews_guard.sql` |
| 38 | `20261102000001_round6_guards_and_kyc.sql` |
| 39 | `20261103000001_relogin_upsert_invariant_and_ambulance_link.sql` |
| 40 | `20261103000002_fix_claim_ambulance_driver_bypass.sql` |
| 41 | `20261103000003_relogin_upsert_invariant_refinement.sql` |
| 42 | `20261103000004_fix_claim_ambulance_driver_and_users_verified_guard.sql` |
| 43 | `20261103000005_remove_scratch_bypass_policies.sql` |
| 44 | `20261103000006_harden_users_guard_orphan_and_unclaimed.sql` |
| 45 | `20261103000007_relax_users_and_admin_users_force_rls.sql` |
| 46 | `20261103000008_staging_anon_security_cleanup.sql` |

**RDS-only overrides** (apply after migrations if replay script detects drift): `db/rds_overrides/*.sql`

---

## 6. Local scratch replay (proof before prod)

```powershell
node scripts/db/rds_scratch_replay.js
```

Recorded result: **0 statement failures**, RLS harness **208/208 PASS** (`docs/ops/test_runs/round10_rds_scratch_replay.txt`).

---

## 7. Seed reference data (production minimum)

Dry-run:

```powershell
node scripts/db/seed_production_minimum.js --dry-run
```

Apply only after operator confirms empty production DB policy.

---

## 8. Post-migrate verification

1. `node scripts/db/schema_diff.js` — staging vs RDS catalog parity  
2. `node scripts/db/anon_surface_audit.js --target=staging` (or `replay` / `production`)  
3. `node scripts/db/rls_sql_harness.js --target=staging`  
4. `node scripts/e2e/postgrest_e2e_runner.js` — 6/6 HTTP tests (`round10_postgrest_e2e.txt`)  
5. Gateway: `cd services/api-gateway && npm test`  
6. Point `APP_ENV=production` Functions at `PROD_GATEWAY_URL` + `PROD_GATEWAY_SERVICE_KEY`

---

## 9. Rollback

| Environment | Action |
|---|---|
| **Staging** | Restore from `backups/staging_logical_*` NDJSON export; re-apply ledger from known good migration version |
| **Production RDS** | Restore RDS snapshot taken **before** migrate; revert ECS gateway to previous task definition |
| **Application** | Set Remote Config `use_supabase_db_doctor_patient=false` only if Firestore fallback still deployed (legacy); preferred: fix-forward on RDS |

Rollback SQL for grants/RLS (do **not** auto-run in migrate): `backend/supabase/rollbacks/20261025000001_least_privilege_grants_and_rls_rollback.sql`

---

## 10. Backup plan

| Tier | Staging (Supabase) | Production (RDS) |
|---|---|---|
| **Logical** | `pg_dump -Fc` or project NDJSON export scripts | `aws rds create-db-snapshot` before cutover |
| **Frequency** | Before each migration batch | Daily automated + pre-cutover manual |
| **Retention** | 30 days off-site | 35 days (adjust per compliance) |
| **Restore test** | Scratch DB replay (`rds_scratch_replay.js`) | Restore to `doctornect-rehearsal` instance quarterly |
