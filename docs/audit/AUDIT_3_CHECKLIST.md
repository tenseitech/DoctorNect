# Audit 3 — Code Quality Checklist (CQ-01 … CQ-06)

**Remediation date:** 2026-11-26 (final pass)  
**Branch:** `audit3/code-quality`  
**Overall:** **COMPLETE**

| ID | Finding | Remediation | Tests | Status |
|----|---------|-------------|-------|--------|
| CQ-01 | S3 callables deploy wiring | Verified exports + `s3_callables_exports.test.js` | **PASS** | **VERIFIED** |
| CQ-02 | `cross_role_sync.js` 4k+ LOC | Split into `*_infra/coerce/payloads/pg.js`; main **3530** LOC | **71 pass** | **REFACTORED** |
| CQ-03 | Hardcoded invite URLs | `AppWebUrls`; lab invite + Telegram default | **14 pass** | **FIXED** |
| CQ-04 | Duplicated delete-account UX | `delete_account_flow.dart` | **3 pass** | **FIXED** |
| CQ-05 | TODO / technical debt | Grep clean (app source) | — | **INFO** |
| CQ-06 | Medibond vs DoctorNect | `BRAND_NAMING_ALIASES.md` | — | **DOCUMENTED** |

**Regression (final):**

```text
cd frontend && flutter analyze --no-pub && flutter test test/app_web_urls_test.dart test/delete_account_flow_test.dart test/invite_deep_link_test.dart
cd backend/functions && node --test test/cross_role_sync.test.js test/doctor_sync.test.js test/pharmacy_lab_sync.test.js test/ambulance_sync.test.js test/user_identity_bridge.test.js test/s3_callables_exports.test.js
```

**Separation:** No changes to Audit 2 commits; Audit 1 `index.js` not modified in final pass.