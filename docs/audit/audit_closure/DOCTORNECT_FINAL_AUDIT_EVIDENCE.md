# DoctorNect — Final Audit Evidence (local execution)

**Generated:** 2026-11-26  
**Machine:** Windows dev host (no Docker CLI, no AWS CLI, no staging credentials)  
**Branch:** `audit-closure/remaining-audits`  
**Script:** `node scripts/audit_closure/run_master_local_verification.js` → `DOCTORNECT_FINAL_AUDIT_EVIDENCE.json`

## Local verification matrix

| Step | Status | Notes |
|------|--------|-------|
| env_parity | **PASS** | 149 documented keys |
| audit1_staging_prereq | **BLOCKED** | Exit 2 — staging vars missing |
| sec07_csp_static | **PASS** | `hosting_csp_connect_src.test.js` 2/2 |
| gateway_unit | **PASS** | 135 tests |
| functions_env_parity | **PASS** | 5/5 |
| alert_templates_validation | **PASS** | Audit 7 templates |
| Docker | **NOT RUN** | `dockerAvailable: false` |

## Additional runs (this pass)

| Command | Result |
|---------|--------|
| `flutter test` (full) | **705/705 PASS** |
| `flutter test --coverage` + gate | **26.25%** lib lines (min 26) **PASS** |
| IconButton inventory | 104 sites, 64 files (`icon_button_inventory.js`) |
| `flutter test test/e2e_auth_welcome_smoke_test.dart` | **PASS** |
| `backend/functions npm test` | **567 pass / 0 fail** (592 total with skips) |

## Staging — not executed

- `audit1_staging_sec04_revocation_e2e.js`
- Hosted CSP browser (SEC-07)
- ECS Redis 429 (SEC-08)
- REL-10 log correlation
- Manual a11y matrix

## Audit 4

**ON HOLD** — no migrations, no infra commits from Audit 4 remediation paths in this pass except unrelated dirty files left unstaged.