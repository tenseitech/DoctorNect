# DoctorNect migration status

**Branch:** `fix/pre-accept-gate-lab-auth`  
**Updated:** 2026-11-17 (DEFINER batch in `000005`; **fresh gate UNVERIFIED** — Docker engine down, prod tunnel down)  
**Evidence:** `docs/audit/DEFINER_FORCE_RLS_CATALOG.md`; `docs/audit/SECURITY_REVIEW_20261118000005.md`.

---

## Pre-check (2026-11-17)

| Check | Status | Proof |
|-------|--------|-------|
| Docker `rdslike-pg18` `:5442` | **FAIL** | `docker ps` → `dockerDesktopLinuxEngine` pipe missing |
| Prod ledger `20261118000005` | **UNVERIFIED** | `ECONNREFUSED 127.0.0.1:5433` (tunnel not up) |
| Staging ledger `20261118000005` | **UNVERIFIED** | no staging read in this run |

Repo migration **not** applied on real ledgers until operator confirms (in-place edit allowed).

---

## DEFINER / `000005` (code)

| Item | Status |
|------|--------|
| FORCE RLS DEFINER set re-homed | **PASS** (code) — **9** functions → `service_role` owner (`docs/audit/DEFINER_FORCE_RLS_CATALOG.md`) |
| Live catalog audit | **UNVERIFIED** | `scripts/db/definer_force_rls_audit.js` needs `:5442` DB |
| Security review | **PASS** (design) | `SECURITY_REVIEW_20261118000005.md` updated |

---

## `doctornect_admin` rehearsal gate

| Step | Status |
|------|--------|
| Full sequence + migrate ledger | **UNVERIFIED** | Docker down |
| Harness **210/0** | **UNVERIFIED** | — |
| Gateway **74/0** | **UNVERIFIED** | 2026-11-16 prior: **74/0** on older `000005` |
| `has_schema_privilege` CREATE | **UNVERIFIED** | — |
| Parity (pg_stat filtered) | **UNVERIFIED** | `schema_diff.js` filter in repo |
| pg_cron local migrate | **UNVERIFIED** | no `pg_cron` in `rdslike-pg18` image |

---

## Migrations repo

| Target | Files | Staging ledger (last known) |
|--------|------:|----------------------------|
| production / rehearsal | **72** | staging **62** rows; pending includes `20261118000005` |

---

## Prod cutover

**prod gates pending (doctornect_admin harness 210/0 unverified, pg_cron cron.database_name unverified)**

- [ ] Fresh `doctornect_admin` rehearsal: gateway **74/0** + harness **210/0**  
- [ ] `migrate.js` **72/72** on prod (no `--allow-no-cron`)  
- [ ] `definer_force_rls_audit.js` exit **0** after migrate  