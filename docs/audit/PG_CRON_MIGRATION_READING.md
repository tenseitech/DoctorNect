# pg_cron — migration reading (no live apply in this doc)

**Source files:** `db/migrations/20260923000003_doctornect_cron.sql`, `db/migrations/20261021000002_phase_d_pharmacy_lab_ambulance.sql` (conditional schedule).

**Local docker:** `scripts/docker/rdslike-pg18` uses `postgres:18` **without** `shared_preload_libraries=pg_cron`. Local rehearsal continues to use `migrate.js --allow-no-cron`. **Live local pg_cron apply: UNVERIFIED** (Docker daemon unavailable in gate run 2026-11-17).

## `20260923000003_doctornect_cron.sql`

| Job name | Schedule (cron) | Command | Tables / functions touched | Runs as |
|----------|-----------------|---------|----------------------------|---------|
| `expire-promoted-ads` | `0 * * * *` (hourly UTC) | `UPDATE promoted_ads SET status='expired', updated_at=now() WHERE status='active' AND end_time <= now()` | `public.promoted_ads` | pg_cron worker in **`cron.database_name`** DB (RDS: typically `doctornect`) |
| `cleanup-expired-otp-challenges` | `0 3 * * *` daily | `DELETE FROM otp_challenges` and `DELETE FROM otp_verification_sessions` where `expires_at < now() - 1 day` | `otp_challenges`, `otp_verification_sessions` | same |
| `cleanup-expired-rate-limits` | `15 3 * * *` daily | `DELETE FROM abuse_rate_limits WHERE window_start < now() - 7 days` | `abuse_rate_limits` | same |

Migration starts with `CREATE EXTENSION IF NOT EXISTS pg_cron;` (requires RDS `shared_preload_libraries` includes `pg_cron`).

## `20261021000002` (only if extension present)

| Job name | Schedule | Command | Objects | Runs as |
|----------|----------|---------|---------|---------|
| `expire-stale-ambulance-broadcasts` | `*/5 * * * *` | `SELECT public.expire_stale_ambulance_broadcasts();` | RPC `expire_stale_ambulance_broadcasts()` → `ambulance_broadcasts` (and related state) | same |

Wrapped in `DO $$ … IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')`.