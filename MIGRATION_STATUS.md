# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-19 — Tasks 1–2 PASS, Gate 1 ready

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging ledger** | **77 / 77** | **100%** |
| **Staging harness** | **210 / 210** | **100%** |
| **Prod RDS migrate** | **0 / 77** | **0%** |
| **Prod bootstrap 01–03** | **partial** (~roles only) | **~50%** |
| **Cutover overall** | — | **~64%** |

---

## Prod read-only (2026-11-19)

| Check | Result |
|-------|--------|
| **`PROD_RDS_DB`** | **`doctornect`** (single line) |
| **Master** | **`doctornect_admin`** (RDS console master) |
| **Dual login** | **OK** (migrator + master password keys) |
| **Identity** | PG **18.3**, DB **doctornect**, port **5432**, SSL **on**, **`rds_superuser` member**, createrole/createdb **true** |
| **Snapshot** | **`<REAL SNAPSHOT ID>`** / **`<REAL UTC TIME>`** |
| **Backup v2** | `...\2026-11-19-v2` — dump **3703 B**, roles **4873 B**, **26** TOC lines |
| **Verdict** | **PARTIAL** — gaps unchanged (see below) |
| **pg_cron** | Preloaded; **`cron.database_name=doctornect`**; extension not installed (pre-migrate) |

### Bootstrap gaps (unchanged vs 2026-11-18)

- **01:** `pgcrypto`, `uuid-ossp`, `pg_stat_statements`; reset grant **false**
- **02:** `auth.jwt()` (and uid/role via 02 script)
- **03:** `auth.users` stub; **private USAGE** for `authenticated`
- **Ledger:** **0** / 77

---

## Gates

| Gate | Status |
|------|--------|
| **Gate 1** `APPROVED FOR PROD: BOOTSTRAP` | **waiting** |
| **Gate 2** `APPROVED FOR PROD: MIGRATE` | not given |

**Next:** Send Gate 1 phrase → bootstrap **01** → **02+03** → dry-run / dry-run-all / preflight.