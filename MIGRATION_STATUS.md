# DoctorNect migration status

**Branch:** `migration-cutover-fixes` (local, **not pushed**)  
**Updated:** 2026-11-18 — Tasks 1–4 bundle run

---

## Migration completion %

| Scope | Applied / total | % |
|-------|-----------------|---|
| **Staging ledger** | **77 / 77** | **100%** |
| **Staging harness** | **210 / 210** | **100%** |
| **Prod RDS migrate** | **unknown / 77** | **0%** (ledger unreadable) |
| **Prod verified forensics** | — | **0%** |
| **Cutover overall** | — | **~55%** |

---

## 2026-11-18 prod read-only session

| Item | Result |
|------|--------|
| `.env` PROD_RDS_* | **OK** — `*.rds.amazonaws.com`, port **5434**, db **doctornect**, no duplicate keys in file |
| Loopback guard | `prod_rds_host_policy.js` + `buildRdsPoolConfig` fail-fast if `PROD_RDS_HOST` is `127.0.0.1` |
| SSM tunnel | **OK** after restart (stale `session-manager-plugin` listener caused **ECONNREFUSED** on first probe) |
| Auth `doctornect_admin` | **28P01** — discrete `pg` params (not URL); wrong password and/or role not created (bootstrap **01**) |
| `PROD_RDS_MASTER_*` | **Not in .env** — master bootstrap inventory **skipped** |
| Forensics / dry-run / backup / pg_cron SQL | **Blocked** on **28P01** |
| `aws rds Describe*` | **AccessDenied** — attach `docs/audit/iam_rds_readonly_policy.json` |
| Bastion SSM `cda2c3fb-…` | **node/git/tmux/nc missing**; **root**; **6.4G** free on `/` |

**Re-run:** `powershell -File scripts/audit/prod_readonly_bundle.ps1`

---

## Staging

Head `20261119000005`; harness **210/0**.

---

## Blocks **APPROVED FOR PROD**

- [x] Staging + replay gates
- [ ] Fix **`PROD_RDS_PASSWORD`** or run bootstrap **01** (master), then re-probe
- [ ] Optional: add **`PROD_RDS_MASTER_USER`** / **`PROD_RDS_MASTER_PASSWORD`** for roles-only dump + inventory
- [ ] IAM RDS read-only OR console for pg_cron/backups
- [ ] Bastion **Node 20+**, **git**, **tmux** (or use laptop tunnel for execute)
- [ ] Forensics, **77** pending dry-run, backup v2
- [ ] **`APPROVED FOR PROD`**