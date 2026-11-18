# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-18 — **GO STAGING** `19000005` applied

---

## Migration completion % (honest)

| Scope | Applied / total | % | Notes |
|-------|-----------------|---|--------|
| **Staging (Supabase)** | **77 / 77** ledger rows | **100%** | Head `20261119000005`; RDS-only `rds/13000001` skipped by design |
| **Staging shared SQL files** | **75 / 75** (+ ghost parity) | **100%** | All repo files for `target=staging` |
| **Prod RDS migrations** | **0 / 77** | **0%** | Tunnel down; not executed |
| **Prod bootstrap 01–03** | unknown | **0%** verified | Forensics skipped |
| **Prod bootstrap 04** | 0 | **0%** | Post-migrate |
| **End-to-end RDS cutover** | — | **~55%** | Staging + replay gates done; prod blocked |

---

## Staging (after `19000005`)

| Check | Result |
|-------|--------|
| Pooler | **5432** session (`aws-0-ap-south-1.pooler.supabase.com`) |
| `rls_sql_harness` | **210 / 0** (`docs/reports/rls_harness_staging_2026-11-18T09-05-49-408Z.md`) |
| System-admin ACL | `authenticated` + `service_role` EXECUTE; `anon` false |
| `gateway_rls` on staging | **N/A** — suite uses local fresh DB only |

---

## Replay (reference)

| Gate | Result |
|------|--------|
| Harness | **210 / 0** (with `19000005`) |
| Gateway | **74 / 0** (replay) |
| Definer | **0** |

---

## Production

| Check | Status |
|-------|--------|
| SSM `:5434` | **Down** — Tasks B/C skipped |
| Prod dry-run / forensics / backup | **Pending tunnel** |

---

## Blocks **APPROVED FOR PROD**

- [x] Staging at head + harness **210/0**
- [ ] Prod tunnel + forensics + preflight + backup v2
- [ ] Bootstrap **01–03** on prod
- [ ] Prod `dry-run-all` (77 pending, incl. `rds/13000001`)
- [ ] Your **`APPROVED FOR PROD`**
- [ ] Prod `execute` + **04** + prod gates