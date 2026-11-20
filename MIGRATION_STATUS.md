# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-20 — **Prod cutover complete**

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