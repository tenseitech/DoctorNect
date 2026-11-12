# Proposed SQL (never auto-applied)

Files here are **excluded** from `scripts/db/migrate.js`, which only scans `db/migrations/*.sql` when run with `--execute`.

Apply proposed scripts manually after review (staging first).

| File | Purpose |
|------|---------|
| `20261103000014_proposed_role_verified_rls_hardening.sql` | Verified doctor/lab/store checks on provider RLS |
| `20261103000015_proposed_lab_report_storage_key.sql` | RPC `p_report_storage_key`; backfill from legacy `notes` |
| `20261103000016_proposed_ambulance_in_app_notifications_supabase.sql` | Postgres tables/RLS for notifications + ambulance client cutover |

There is **no** `20261103000013` in this repository (superseded conceptually by `000014`).
