# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-19 — prod login + inventory (read-only)

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging ledger** | **77 / 77** | **100%** |
| **Staging harness** | **210 / 210** | **100%** |
| **Prod RDS migrate** | **0 / 77** | **0%** |
| **Prod bootstrap 01–03** | **partial** | **~50%** (roles yes; ext + 02/03 gaps) |
| **Cutover overall** | — | **~63%** |

---

## Prod read-only (2026-11-19)

| Check | Result |
|-------|--------|
| **`PROD_RDS_MASTER_USER` on disk** | **`doctornect_admin`** (not `postgres` — save `.env` after edit) |
| **`postgres` + `PROD_RDS_MASTER_PASSWORD`** | **28P01** |
| **`doctornect_admin` + `PROD_RDS_PASSWORD`** | **28P01** (migrator slot out of sync) |
| **`doctornect_admin` + `PROD_RDS_MASTER_PASSWORD`** | **OK** (password is migrator secret today, not RDS master) |
| RDS manual snapshot | **`<REAL SNAPSHOT ID>`** / **`<REAL UTC TIME>`** (as reported) |
| SSM tunnel | Started **PID 21212**, closed after run |
| Verdict | **PARTIAL** — unchanged gaps vs 2026-11-18 |
| **pg_dumpall as postgres** | **NOT RUN** (blocked at **28P01**) |
| **Backup folder** | `C:\Users\khije\Backups\doctornect-prod-2026-11-19-v2` — failed **postgres** dump (**0** B stub); use **2026-11-18-v2** data dump until fixed |

### Inventory gaps (unchanged)

- **01:** `pgcrypto`, `uuid-ossp`, `pg_stat_statements`; `pg_stat_statements_reset` grant **false**
- **02:** `auth.jwt()`
- **03:** `auth.users` stub; **private USAGE** for `authenticated`
- **Ledger:** **0**; **pg_cron** preload **OK**

---

## Gates

| Gate | Status |
|------|--------|
| **Gate 1** `APPROVED FOR PROD: BOOTSTRAP` | **not given** |
| **Gate 2** `APPROVED FOR PROD: MIGRATE` | not given |

**Blocker before Gate 1:** RDS master username **`postgres`** in `PROD_RDS_MASTER_USER`; **`PROD_RDS_MASTER_PASSWORD`** = RDS master password (Console → modify master password if needed); **`PROD_RDS_PASSWORD`** = `doctornect_admin` after `\password`. Save `.env`.

---

## Staging

Head `20261119000005`; harness **210/0**.