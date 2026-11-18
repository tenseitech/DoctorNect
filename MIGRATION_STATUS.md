# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-18  
**Overall (staging ledger):** **62 / 75 ≈ 83%** applied (13 SQL files pending on staging track, incl. 4 gate-fix migrations)

---

## Corrections

| Issue | Fix |
|-------|-----|
| Prod forensics “ledger 72 / full schema” | **Bleed from `:5442` replay** when `PROD_RDS_PORT` was wrong. Script now **HARD_ABORT** unless port **5434**, TLS on, `rds_superuser` present, server **18.3**. |
| Earlier **3.7 KB** `pg_dump` | TOC shows **18.3** RDS + tiny schema (only `_schema_migrations`). Confirmed **legit prod-empty** snapshot; **not** Docker. Redo dump when `:5434` tunnel up. |

---

## Task 1 (staging / replay)

| Item | Status |
|------|--------|
| `20261118000002` policy guard | **Done** (edited in place; `000006` **removed**) |
| `20261116000001` role stubs | **Reverted** (were for dry-run on Supabase; **not** needed after `000002` guard) |
| Staging `dry-run-all` | **PASS** — **13** pending files, **80** stmts, **0** errors *(was “10” before gate migrations `20261119…`)* |
| Fresh replay | bootstrap **01–03** → migrate → **04** (`rdsadmin`) + gate SQL |

---

## Gates (replay `:5442`, latest)

| Gate | Result |
|------|--------|
| `gateway_rls_authorization_suite` | **74 / 0** |
| `rls_sql_harness` | **196 / 14** (not **210/0**) |
| `definer_force_rls_audit` | **0 hits**, exit **0** (after `19000003` + `19000004`) |

---

## Production RDS (read-only)

| Check | Status |
|-------|--------|
| SSM `:5434` | **Down** this session (`TcpTestSucceeded: False`) |
| Forensics script | **HARD_ABORT** without tunnel / TLS — **no new prod row counts** |
| Bootstrap on prod | **01** partial (roles); **02** + **03** **missing** (`auth.jwt`, legacy compat) |
| Verdict (last trusted `:5434` read) | **PARTIAL** — empty ledger, no app data |

---

## Step D blockers (staging `--execute`)

1. **Replay harness** not **210/0** (14 fails: mostly cross-tenant RPC **P0002 vs 42501**, appointment reschedule RLS).  
2. **`19000001`–`19000004`** on staging track — need product sign-off before staging apply.  
3. **Prod** bootstrap **02–03** + gates + explicit **"APPROVED FOR PROD"**.  
4. **Operator OK** to merge `migration-cutover-fixes` (commits on branch, not `main`).

---

## Commits on `migration-cutover-fixes` (7)

1. `000002` policy guard  
2. `generate_rds_runtime_grants` + `04`  
3. `definer_force_rls_audit` TypeError  
4. `19000001` promoted_ads  
5. `19000002` anon discovery EXECUTE  
6. `19000003` RPC rehome batch  
7. `19000004` signature fix + prod forensics guards  