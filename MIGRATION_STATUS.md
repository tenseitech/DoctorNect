# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-18 (tunnel check — prod Tasks A–C **NOT RUN**)

---

## Tunnel

`Test-NetConnection 127.0.0.1:5434` → **False** (this session). Prod read-only forensics, dry-run, backup, AWS, and pg_cron SQL **skipped**.

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging Supabase ledger** | **77 / 77** | **100%** |
| **Staging shared SQL files** (`target=staging`) | **75 / 75** | **100%** |
| **Prod RDS migrate ledger** | **0 / 77** | **0%** |
| **Prod bootstrap 01–03** | unverified (NOT RUN) | **—** |
| **Prod bootstrap 04** | 0 | **0%** |
| **Cutover (staging + gates + prod path)** | — | **~55%** |

---

## Staging (confirmed)

| Item | Result |
|------|--------|
| Head | `20261119000005` |
| `rls_sql_harness` | **210 / 0** |

---

## Production (NOT RUN today)

| Item | Status |
|------|--------|
| Forensics / preflight / dry-run | **NOT RUN** (tunnel) |
| Backup v2 / AWS RDS describe | **NOT RUN** |
| pg_cron live parameter/SQL check | **NOT RUN** |

---

## Docs added for cutover day

- `docs/runbooks/PROD_CUTOVER_DAY_PLAN.md` — numbered timeline, failures, tunnel advice
- `docs/PR_SUMMARY_migration-cutover-fixes.md` — branch PR draft

---

## Next

1. Bring up **SSM tunnel :5434** and re-run Tasks A–C (read-only).  
2. Complete pg_cron parameter group + reboot if SQL checks fail.  
3. Bootstrap 01–03 → `dry-run-all` → backup → **`APPROVED FOR PROD`** → execute.