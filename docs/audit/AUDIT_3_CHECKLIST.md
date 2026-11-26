# Audit 3 — Code Quality Checklist (CQ-01 … CQ-06)

**Remediation date:** 2026-11-26  
**Branch:** `audit2/docker-ci-evidence` (Audit 3 work isolated in commit; branch rename to `audit3/code-quality` optional)  
**Overall:** **PARTIALLY COMPLETE** (CQ-02 large-file splits deferred)

| ID | Finding | Remediation | Tests | Status |
|----|---------|-------------|-------|--------|
| CQ-01 | S3 callables deploy wiring | Verified `index.js` re-exports; `s3_callables_exports.test.js` | `node --test test/s3_callables_exports.test.js` **PASS** | **VERIFIED** (implements Audit 1 SEC-10; Audit 1 **not closed**) |
| CQ-02 | Mega-modules (4k+ LOC) | Documented inventory; no risky split this pass | N/A | **OPEN** (debt documented) |
| CQ-03 | Hardcoded invite URLs | `AppWebUrls` + `--dart-define=PUBLIC_WEB_ORIGIN` | `flutter test` invite + `app_web_urls_test` **PASS** | **FIXED** |
| CQ-04 | Duplicated delete-account UX | `delete_account_flow.dart` shared flow | `delete_account_flow_test.dart` **PASS** | **FIXED** |
| CQ-05 | TODO / technical debt | Grep: negligible in `lib/` + functions | N/A | **INFO** (strength retained) |
| CQ-06 | Medibond vs DoctorNect | `docs/audit/BRAND_NAMING_ALIASES.md` | N/A | **DOCUMENTED** |

**Regression (2026-11-26):**

```text
cd frontend && flutter analyze --no-pub          # No issues found
cd frontend && flutter test test/app_web_urls_test.dart test/delete_account_flow_test.dart test/invite_deep_link_test.dart  # 14 pass
cd backend/functions && node --test test/s3_callables_exports.test.js  # 1 pass
```

**Separation:** Audit 3 did **not** modify Audit 2 committed files (`081ae77`, `e9c42b7`). Audit 1 `index.js` / `s3_storage.js` left as existing working-tree remediation (not re-edited for Audit 3).