# PR summary: `migration-cutover-fixes` (prepare only — not pushed)

## Purpose

Align Supabase staging with RDS replay gates, harden prod forensics, fix staging harness gaps, and document prod cutover. Staging ledger at **`20261119000005`** with **210/0** harness.

## Commits (newest first)

| Commit | Summary |
|--------|---------|
| `1ad1e82` | MIGRATION_STATUS: staging 77/77, harness 210/0 |
| `a205e2a` | Fix PROD_CUTOVER_RUNBOOK flags, pg_cron, master for 01 |
| `a4d9014` | Staging ACL verify script for system-admin helpers |
| `3e9d327` | Status: pending 19000005, replay green |
| `47538fa` | Prod cutover runbook + compare_private_helper_acl audit |
| `c052559` | Migration **19000005** system admin EXECUTE grants |
| `7d7649b` | Status after GO STAGING 14-file execute |
| `ea36eb3` | Regenerate bootstrap **04** (prescription children, ambulance_location, anon discovery EXECUTE) |
| `76234e4` | Status: forensics bleed fix |
| `643ed4b` | **19000004** RPC signature re-home; prod forensics HARD_ABORT |
| `104857e` | **19000003** DEFINER re-home batch 1 |
| `0ef23f0` | **19000002** anon discovery grants after 04 |
| `d40fdac` | **19000001** promoted_ads carousel paid-only SELECT |
| `7f26fa1` | definer_force_rls_audit execute_roles fix |
| `07d1caf` | generate_rds_runtime_grants: pharmacy_delivery_medicines, ambulance_invites |
| `d027e95` | **18000002** guard when RDS roles missing |

## Migrations / gates (what each does)

| Version | File | Effect |
|---------|------|--------|
| `18000002` | doctor_directory_security_definer_function | DEFINER directory; DO guard if roles missing (dry-run safe) |
| `19000001` | promoted_ads_carousel_paid_only | Non-owners cannot SELECT `active` + `payment_status=pending` ads |
| `19000002` | anon_discovery_function_grants_after_bootstrap_04 | Re-grant anon `doctor_directory_rows()` EXECUTE after 04 REVOKE |
| `19000003` | rpc_rehome_force_rls_definer_to_service_role | OWNER → `service_role` for FORCE RLS DEFINER RPCs/triggers |
| `19000004` | rpc_rehome_force_rls_signatures_fix | Correct signatures + more RPCs (prescription, ambulance location) |
| `19000005` | system_admin_helper_execute_grants | `GRANT EXECUTE` on `is_system_admin_user` + user protection triggers (staging 11→0 harness fails) |

## Non-migration files

- `db/rds_bootstrap/04_rds_runtime_grants.sql` — regenerated grants
- `scripts/audit/_prod_greenfield_readonly.js` — refuse Docker `:5442` bleed on prod forensics
- `scripts/db/definer_force_rls_audit.js` — PG array parsing fix
- `scripts/db/generate_rds_runtime_grants.js` — template fixes
- Runbooks: `PROD_CUTOVER_RUNBOOK.md`, `PROD_CUTOVER_DAY_PLAN.md`

## Test evidence

- Staging: migrate execute through `19000005`; **rls_sql_harness 210/0**
- Replay (docker `:5442`): bootstrap + migrate + 04; **210/0**, gateway **74/0**, definer **0**
- Prod: **not executed** (tunnel / approval)

## Merge notes

- Do **not** merge without prod cutover checklist green and **`APPROVED FOR PROD`**
- Branch is **local only** until you push and open PR