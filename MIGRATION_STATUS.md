# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-19 — **Gate 1 complete**; **Gate 2 waiting**

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging ledger** | **77 / 77** | **100%** |
| **Staging harness** | **210 / 210** | **100%** |
| **Prod bootstrap 01–03** | **applied** | **~100%** (04 after migrate) |
| **Prod RDS migrate** | **0 / 77** | **0%** |
| **Cutover overall** | — | **~72%** |

---

## Gate 1 (2026-11-19) — DONE

| Step | Result |
|------|--------|
| **01** `01_roles_and_extensions.sql` | **OK** (psql, `doctornect_admin`) |
| **Post-01** | Extensions **pgcrypto, uuid-ossp, pg_stat_statements**; **supabase_realtime** pub; 6 roles; **`pg_stat_statements_reset()`** not on PG **18.3** RDS (grant N/A) |
| **02+03** `rds_bootstrap_apply.js` | **OK** |
| **Post-02/03** | **auth.jwt** shim OK; gaps **02/03 null**; **AUTH_SHIM_JWT true**; ledger **0** |
| **dry-run** | **77** pending incl. **`rds/20261113000001`**; ledger **0** |
| **dry-run-all** | **FAIL** — **451** statement errors on **scratch DB** (no bootstrap on scratch) — see runbook |
| **preflight** | See latest run output |

**Snapshot:** `<REAL SNAPSHOT ID>` / `<REAL UTC TIME>`

---

## Gates

| Gate | Status |
|------|--------|
| **Gate 1** `APPROVED FOR PROD: BOOTSTRAP` | **completed** |
| **Gate 2** `APPROVED FOR PROD: MIGRATE` | **waiting** |

**Before Gate 2:** Resolve **dry-run-all** scratch-bootstrap gap (code or approved workaround). Then **`migrate --execute`** + **bootstrap 04** + harness.

---

## Staging

Head `20261119000005`; harness **210/0**.