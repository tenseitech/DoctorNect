# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-18 — prod read-only bundle (tasks 1–4)

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging ledger** | **77 / 77** | **100%** |
| **Staging harness** | **210 / 210** | **100%** |
| **Prod RDS migrate** | **0 / 77** | **0%** |
| **Prod bootstrap 01–03** | **partial** (roles yes; extensions + 02/03 gaps) | **~45%** |
| **Cutover overall** | — | **~62%** |

---

## Prod read-only (2026-11-18)

| Check | Result |
|-------|--------|
| `PROD_RDS_MASTER_USER` / `PROD_RDS_MASTER_PASSWORD` | **present** in `env_loader`; no placeholder pattern |
| **Warning** | `PROD_RDS_MASTER_USER` is **`doctornect_admin`**, not RDS instance master **`postgres`** — works for inventory but **`pg_dumpall --roles-only` fails** (`pg_authid`); bootstrap **01** must use **postgres** + real master secret |
| SSM tunnel **5434** | **TCP OK** (reused existing forward; no new agent PID) |
| Verdict | **PARTIAL** — PG **18.3**, `rds_superuser=true`, SSL via tunnel, logical host `doctorne….amazonaws.com` |
| `doctornect_admin` | **exists**, `rolcanlogin=true`, createrole/createdb, no bypassrls |
| Bootstrap **01** | All six roles present; extensions **`pgcrypto` / `uuid-ossp` / `pg_stat_statements`** **missing**; reset grant **false** |
| Bootstrap **02** | **`auth.jwt()`** missing (`auth` schema present) |
| Bootstrap **03** | **`auth.users` stub**, **`GRANT USAGE ON SCHEMA private TO authenticated`** missing |
| Ledger | **0** rows; public user tables **0** (empty `_schema_migrations` only) |
| **pg_cron** | **Preloaded** (`pg_cron` in `shared_preload_libraries`); **`cron.database_name=doctornect`**; extension **not installed** (expected pre-migrate) |
| Backup v2 | `C:\Users\khije\Backups\doctornect-prod-2026-11-18-v2` — dump **3703** bytes, **15** TOC entries (**26** list lines); **`pg_dumpall` roles FAIL** (non-superuser) |
| Path | **Not Path A** (role exists). **Path B** for app creds + **Gate 1** still required for **01/02/03** gaps |

---

## Staging

Head `20261119000005`; harness **210/0**.

---

## Gates

| Gate | Status |
|------|--------|
| **Gate 1** `APPROVED FOR PROD: BOOTSTRAP` | **not given** — waiting |
| **Gate 2** `APPROVED FOR PROD: MIGRATE` | not given |

**Next:** Set **`PROD_RDS_MASTER_USER=postgres`** and real RDS master password (save `.env`, do not commit). Align **`PROD_RDS_PASSWORD`** with `doctornect_admin`. Confirm manual RDS snapshot time. Then Gate 1.