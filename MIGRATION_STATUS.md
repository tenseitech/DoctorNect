# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-18 after **GO STAGING** execute  
**Staging ledger:** **76 / 76 = 100%** on Supabase track (62 → **76**, head **`20261119000004`**)

---

## Staging execute (GO STAGING)

| Step | Result |
|------|--------|
| Pooler | **5432** session (`aws-0-ap-south-1.pooler.supabase.com`) |
| `--execute` | **14 / 14** applied, **0** failures |
| Post `dry-run` | **0** pending |
| `rls_sql_harness --target=staging` | **199 / 11** (see report) |

---

## Replay gates (reference)

| Gate | Result |
|------|--------|
| Harness | **210 / 0** |
| Gateway | **74 / 0** |
| Definer audit | **0** hits |

---

## Production RDS

| Check | Status |
|-------|--------|
| SSM `:5434` | **Down** (this session) — forensics + dump **skipped** |
| Prod migrate | **Blocked** until **"APPROVED FOR PROD"** + bootstrap **02/03** + replay gates on prod path |

---

## Prod readiness checklist

- [x] Staging schema at head (`20261119000004`)  
- [x] Replay gates green (210/0, 74/0, definer 0)  
- [ ] Staging harness parity (11 fails — `is_system_admin_user` on Supabase)  
- [ ] Prod SSM tunnel + forensics + backup  
- [ ] Bootstrap **01–03** on prod RDS  
- [ ] **"APPROVED FOR PROD"**  
- [ ] Prod migrate **72/72** (+ RDS-only file) + post-migrate **04**  