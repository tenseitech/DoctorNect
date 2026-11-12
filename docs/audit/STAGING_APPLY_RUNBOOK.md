# Staging apply runbook — proposed SQL 000014–000018

**Scope:** Supabase **staging** project only. **Never** run against production RDS (`doctornect-prod`).

## Prerequisites

| Item | Owner |
|------|--------|
| Staging Postgres connection string (`SUPABASE_DB_URL` or `DATABASE_URL` in repo `.env`) | Owner |
| `psql` 14+ on PATH | Owner or Cursor |
| Staging seed users/fixtures for probes (`uid_doc_verified`, `n_staging_1`, etc.) | Owner |

**Cursor:** may run probes **only if** `DATABASE_URL` / `SUPABASE_DB_URL` in workspace `.env` points at **staging** (hostname contains `supabase` and not prod RDS). This workspace: **check `.env` before any apply** — if missing, owner runs all `psql` steps.

---

## Apply order (owner or Cursor with staging URL)

From repo root, set:

```powershell
$env:PGPASSWORD = "<from staging connection string>"
$STAGING = "postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:6543/postgres"
```

### 1. `000014` — `db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql`

```powershell
psql "$STAGING" -v ON_ERROR_STOP=1 -f db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/pdl_000014_staging_probes.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/rls_staging_verified_role_matrix.sql
```

**Rollback (owner):** re-apply policies from `db/migrations/20261103000011_doctors_select_least_privilege.sql` and consolidated `patient_doctor_links` policy from `db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql` (sections `pdl_select`, appointment/prescription policies touched by 000014).

### 2. `000015` — `db/proposed/20261103000015_proposed_lab_report_storage_key.sql`

```powershell
psql "$STAGING" -v ON_ERROR_STOP=1 -f db/proposed/20261103000015_proposed_lab_report_storage_key.sql
```

**Rollback:** restore `update_lab_order_status` / `update_lab_booking_status` from `db/migrations/20261026000001_rpc_null_safe_authz.sql` (pre-000015 bodies via `scripts/db/rpc_proposed_unified_diff.js` baseline).

### 3. `000016` — `db/proposed/20261103000016_proposed_in_app_notifications_supabase.sql`

```powershell
psql "$STAGING" -v ON_ERROR_STOP=1 -f db/proposed/20261103000016_proposed_in_app_notifications_supabase.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/in_app_notifications_staging_probes.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/trusted_patch_function_privileges.sql
```

**Rollback:**

```sql
DROP TRIGGER IF EXISTS trg_in_app_notifications_recipient_read_only ON public.in_app_notifications;
DROP FUNCTION IF EXISTS private.in_app_notifications_enforce_recipient_read_only();
DROP FUNCTION IF EXISTS public.patch_in_app_notification_server(TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.reconcile_in_app_notification_for_recipient(TEXT, BOOLEAN, TIMESTAMPTZ);
-- Restore policies from db/migrations/20261021000004_phase_e2_support_and_notifications.sql
```

### 4. `000017` — `db/proposed/20261103000017_proposed_rpc_verified_checks.sql`

```powershell
psql "$STAGING" -v ON_ERROR_STOP=1 -f db/proposed/20261103000017_proposed_rpc_verified_checks.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/create_prescription_atomic_staging_probes.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/rpc_verified_staging_probes.sql
```

**Rollback:** restore each RPC from `db/migrations/20261026000001_rpc_null_safe_authz.sql` (or last deployed migration on staging before 000017).

### 5. `000018` — `db/proposed/20261103000018_proposed_lab_report_key_column_guard.sql`

```powershell
psql "$STAGING" -v ON_ERROR_STOP=1 -f db/proposed/20261103000018_proposed_lab_report_key_column_guard.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/lab_report_key_staging_probes.sql
```

**Rollback:**

```sql
DROP TRIGGER IF EXISTS trg_lab_orders_report_key_rpc_only ON public.lab_orders;
DROP TRIGGER IF EXISTS trg_lab_bookings_report_key_rpc_only ON public.lab_bookings;
DROP FUNCTION IF EXISTS private.guard_lab_report_storage_key_column();
```

---

## Full probe sweep (after all applies)

```powershell
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/pdl_000014_staging_probes.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/in_app_notifications_staging_probes.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/create_prescription_atomic_staging_probes.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/lab_report_key_staging_probes.sql
psql "$STAGING" -v ON_ERROR_STOP=1 -f scripts/audit/rpc_verified_staging_probes.sql
```

Expect `NOTICE:  PASS [...]` lines; any `FAIL` raises and rolls back within each probe file (`BEGIN`/`ROLLBACK`).

---

## Cursor automation note

If no staging `DATABASE_URL` in `.env`: **NOT RUN** — owner executes commands above and pastes `psql` output into PR/audit thread.
