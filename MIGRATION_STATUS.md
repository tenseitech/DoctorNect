# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-20 — Gate 2 readiness

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging ledger** | **77 / 77** | **100%** |
| **Staging harness** | **210 / 210** | **100%** |
| **Prod bootstrap 01–03** | **done** | **100%** |
| **Prod dry-run-all** | **0 errors** (scratch + bootstrap fix) | **PASS** |
| **Prod RDS migrate** | **0 / 77** | **0%** |
| **Cutover overall** | — | **~78%** |

---

## Prod (2026-11-20)

| Check | Result |
|-------|--------|
| **Gate 1** | **Complete** (01–03 on `doctornect`) |
| **dry-run-all** | **0 errors**, **1718** statements, **76** files exercised + **cron** skipped on scratch only |
| **doctornect post-check** | **0** `migrate_scratch_*` DBs, ledger **0**, tripwire **7** catalog objects (unchanged) |
| **Inventory** | Bootstrap gaps **02/03 cleared**; extensions **3/3**; ledger **0** |
| **pg_cron** | Preloaded; extension installs on **`--execute`** in `doctornect` only |
| **Snapshot** | `<REAL SNAPSHOT ID>` / `<REAL UTC TIME>` |

---

## Gates

| Gate | Status |
|------|--------|
| **Gate 1** | **done** |
| **Gate 2** `APPROVED FOR PROD: MIGRATE` | **waiting** |

---

## Staging

Head `20261119000005`; harness **210/0`.