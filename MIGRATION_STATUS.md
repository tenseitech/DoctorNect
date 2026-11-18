# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-18 — `prod_readonly_bundle.ps1` run

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging Supabase ledger** | **77 / 77** | **100%** |
| **Staging harness** | **210 / 210** | **100%** |
| **Prod RDS migrate** | **unknown / 77** | **0%** (DB auth blocked forensics) |
| **Prod bootstrap 01–03** | unknown | **not verified** |
| **End-to-end cutover** | — | **~55%** |

---

## Bundle run (2026-11-18)

| Step | Result |
|------|--------|
| AWS STS | **PASS** (`doctornect-admin`) |
| SSM tunnel `:5434` | **PASS** (script starts or reuses `session-manager-plugin`) |
| Bastion `i-0248ed3a2aad183be` | **running**, SSM **Online**, AL2023 agent |
| RDS SQL (doctornect_admin) | **FAIL** `28P01` — fix `PROD_RDS_PASSWORD` / create role in bootstrap **01** |
| `migrate --dry-run` | Guard **PASS**; connect **FAIL** (same auth) |
| `pg_dump` v2 | **FAIL** (auth) |
| `aws rds describe-*` | **FAIL** `AccessDenied` — needs `rds:DescribeDBInstances`, `DescribeDBParameters`, `DescribeDBSnapshots` |
| `.env` hygiene | **Warning:** duplicate `PROD_RDS_HOST` — bundle uses `_resolve_prod_rds_endpoint.js` (prefer `*.rds.amazonaws.com`) |

**Script:** `scripts/audit/prod_readonly_bundle.ps1` (re-run after credentials + IAM fix).

---

## Staging (unchanged)

Head `20261119000005`; harness **210/0**.

---

## Blocks **APPROVED FOR PROD**

- [x] Staging + replay gates
- [ ] Valid **`PROD_RDS_PASSWORD`** for `doctornect_admin` through tunnel
- [ ] Prod forensics + pending **77** count
- [ ] Backup v2
- [ ] AWS RDS read-only IAM (or console checks)
- [ ] pg_cron parameter verification
- [ ] Bootstrap **01–03** + `dry-run-all` + approval + execute