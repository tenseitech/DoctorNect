# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-19 — connection verify (STOP at db name)

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging ledger** | **77 / 77** | **100%** |
| **Staging harness** | **210 / 210** | **100%** |
| **Prod RDS migrate** | **0 / 77** | **0%** |
| **Prod bootstrap 01–03** | **partial** | **~50%** |
| **Cutover overall** | — | **~63%** |

---

## Prod (2026-11-19)

| Check | Result |
|-------|--------|
| RDS master (console) | **`doctornect_admin`** (not `postgres`) |
| **`PROD_RDS_MASTER_USER` / `PROD_RDS_USER`** | **`doctornect_admin`** |
| **`PROD_RDS_DB` on disk** | **`doctornect-prod`** — **FAIL** (must be **`doctornect`**) |
| Logins | **`3D000`** (wrong database name) — auth not reached |
| Snapshot | **`<REAL SNAPSHOT ID>`** / **`<REAL UTC TIME>`** |
| Tunnel | SSM **PID 7232** (closed after run) |
| Inventory / backup v2 | **NOT RUN** (blocked at Task 1) |

**Fix:** Set **`PROD_RDS_DB=doctornect`**, save `.env`, re-run `node scripts/audit/_prod_dual_login_readonly.js`.

Last inventory (2026-11-18): **PARTIAL** — extensions + 02/03 gaps; ledger **0**; pg_cron preload **OK**.

---

## Gates

| Gate | Status |
|------|--------|
| **Gate 1** `APPROVED FOR PROD: BOOTSTRAP` | not given |
| **Gate 2** `APPROVED FOR PROD: MIGRATE` | not given |

---

## Staging

Head `20261119000005`; harness **210/0**.