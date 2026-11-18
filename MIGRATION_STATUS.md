# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-18 — master inventory attempt

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging ledger** | **77 / 77** | **100%** |
| **Staging harness** | **210 / 210** | **100%** |
| **Prod RDS migrate** | **unknown / 77** | **0%** |
| **Cutover overall** | — | **~55%** |

---

## Prod read-only (2026-11-18 evening)

| Check | Result |
|-------|--------|
| `PROD_RDS_MASTER_USER` | **present** (`postgres`) |
| `PROD_RDS_MASTER_PASSWORD` | **present** — **placeholder detected** (`<`, `>`, or literal placeholder text); replace with real RDS master password |
| SSM tunnel **5434** | **OK** (started PID closed after run) |
| `_prod_master_inventory_readonly.js` | **STOP** — SQLSTATE **28P01** (master auth failed) |
| Greenfield / backup / pg_cron SQL | **NOT RUN** (blocked at master) |
| Path A vs B | **NOT RUN** (need successful master session) |

---

## Staging

Head `20261119000005`; harness **210/0**.

---

## Gates

| Gate | Status |
|------|--------|
| **Gate 1** `APPROVED FOR PROD: BOOTSTRAP` | not given |
| **Gate 2** `APPROVED FOR PROD: MIGRATE` | not given |

**Next:** Fix real master password in `.env` (save, do not commit). Re-run master inventory. Confirm manual RDS snapshot time with you.