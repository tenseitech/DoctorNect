# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-18 (Task A/B/C — `19000005` drafted, **not** applied on staging)

---

## Ledger / progress

| Track | State | % |
|-------|--------|---|
| **Staging Supabase** | **76 / 77** applied (head `20261119000004`; pending **`20261119000005`**) | **~99%** schema ledger |
| **Replay (fresh :5442)** | **76** ledger rows + **04**; gates **210/0**, **74/0**, definer **0** with **`19000005`** | **100%** gate path |
| **Prod RDS** | Tunnel **down**; migrate **0** | **~0%** prod DB |

**Overall cutover readiness:** **~52%** (staging almost at head; prod path blocked).

---

## Staging harness (pre-`19000005`)

| Gate | Result |
|------|--------|
| `rls_sql_harness` | **199 / 11** — all `permission denied for function is_system_admin_user` |
| Root cause | `20261112000001` creates helpers with no `GRANT EXECUTE`; `20260930000001` default revoke on Supabase (`postgres` owner) |
| Fix (branch) | `20261119000005_system_admin_helper_execute_grants.sql` — **dry-run-all 0 errors**; **await OK** for `--execute` |

---

## Production

| Check | Status |
|-------|--------|
| SSM `:5434` | **Down** — forensics + `pg_dump` v2 **skipped** |
| Prod file list (repo) | **77** migrations (incl. `rds/20261113000001`); gate files **19000001–05** all on prod track |
| Runbook | `docs/runbooks/PROD_CUTOVER_RUNBOOK.md` |

---

## Prod readiness (blocks **APPROVED FOR PROD**)

- [ ] Staging `--execute` for **`19000005`** + harness **210/0**
- [ ] Prod SSM tunnel + forensics + backup v2
- [ ] Bootstrap **01–03** on prod
- [ ] **`APPROVED FOR PROD`** from you
- [ ] Prod migrate + **04** + gates on prod
- [x] Replay green with **`19000005`** (2026-11-18 fresh docker replay)