# DoctorNect migration status

## Current (2026-11-26, branch `security/full-audit-fix`, not pushed)

| Target | Head | Pending |
|---|---|---|
| Repo (`db/migrations`) | `20261126000002` (86 files) | - |
| Staging Supabase (PG17) | `20261125000004` (read-only check 2026-11-26) | `20261126000001` (reschedule fix), `20261126000002` (FK indexes) |
| Production RDS (PG18) | `20261119000005` (last verified 2026-11-20) | the seven `20261124000001` ... `20261125000004` files plus the two above (9) |

All 86 migrations replay on scratch PG17 and PG18 (`npm run test:db`), the newest are idempotent
and `db/tests` pass. Apply with `scripts/db/migrate.js` (staging first, then RDS after a snapshot):
see docs/GATEWAY_DEPLOY.md "What is left" steps 2-4.

## History (2026-11-20 cutover; superseded by the table above)

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-20 — **Prod cutover complete**  
**Staging:** 2026-11-20 — Supabase demo-only reset (5× `rev_fb_*_001`, no staging super admin row).

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging ledger** | **77 / 77** | **100%** |
| **Staging harness** | **210 / 210** | **100%** |
| **Prod ledger** | **77 / 77** | **100%** |
| **Prod bootstrap 01–04** | **done** | **100%** |
| **Prod RLS harness** | **210 / 0** | **100%** |
| **Cutover overall** | — | **~100%** |

---

## Prod (2026-11-20 Gate 2)

| Step | Result |
|------|--------|
| **migrate --execute** | **77/77** applied · head **`20261119000005`** |
| **dry-run pending** | **0** |
| **Bootstrap 04** | **OK** (`doctornect_admin`, host/hostaddr TLS) |
| **pg_cron** | Installed · **4** jobs (names in runbook report) |
| **definer_force_rls_audit** | **0** DML hits |
| **rls_sql_harness** | **210 PASS / 0 FAIL** |
| **rds_readiness_probe** | **OK** |
| **Post backup** | `...\doctornect-prod-2026-11-19-post` · dump **~523 KB** · **965** TOC lines |
| **Snapshot** | **User-confirmed** `<REAL SNAPSHOT ID>` @ `<REAL UTC TIME>` (AWS CLI not verified) |

---

## Gates

| Gate | Status |
|------|--------|
| **Gate 1** BOOTSTRAP | **done** |
| **Gate 2** MIGRATE | **done** |

---

## Staging

Head `20261119000005`; harness **210/0** (parity with prod).