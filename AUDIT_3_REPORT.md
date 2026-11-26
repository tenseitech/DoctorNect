# Audit 3 — Code Quality, Remediation & Regression

**Date:** 2026-11-26  
**Scope:** CQ-01 … CQ-06 per `CODEBASE_AUDIT_REPORT.md` § AUDIT 3  
**Overall status:** **PARTIALLY COMPLETE** (CQ-02 mega-module splits deferred)

---

## Executive summary

Audit 3 inspected the live codebase, applied safe maintainability fixes on the Flutter client (central web URLs, shared delete-account flow), verified Functions S3 callable wiring without altering Audit 1 security logic, documented brand aliases and remaining large-file debt, and ran targeted regression tests. Audit 1 remains **NOT CLOSED**; Audit 2 remains **OPEN** (no GHA/Docker evidence). No merge to `main`, no deploy, no production account deletion.

---

## CQ findings table

| ID | Severity | Original finding | Root cause | Remediation | Status |
|----|----------|------------------|------------|-------------|--------|
| CQ-01 | High | S3 callables not in deploy entry | `index.js` missing re-exports (overlaps SEC-10) | **Verified** wiring: `require('./s3_storage')` + `exports.getS3*`; test `s3_callables_exports.test.js` | **VERIFIED** (Audit 1 owns SEC-10 closure) |
| CQ-02 | Medium | God-modules 4k+ LOC | Domain logic concentrated | Inventory: `cross_role_sync.js` **4294** lines; `patient_profile_screen.dart` **2213**; no split this pass | **OPEN** |
| CQ-03 | Medium | Hardcoded `doctornect.com` invite URLs | No central client config | `AppWebUrls` + `PUBLIC_WEB_ORIGIN` dart-define | **FIXED** |
| CQ-04 | Medium | Duplicate delete-account UI/errors | Copy-paste across 5 profile screens | `delete_account_flow.dart` | **FIXED** |
| CQ-05 | Low | TODO debt | — | Grep: **no** TODO/FIXME in `frontend/lib` or `backend/functions/*.js` | **INFO** |
| CQ-06 | Low | Medibond vs DoctorNect | Legacy package/Firebase IDs | `docs/audit/BRAND_NAMING_ALIASES.md` | **DOCUMENTED** |

---

## CQ-01 — S3 callable wiring

**Files:** `backend/functions/index.js` (Audit 1 working tree), `backend/functions/s3_storage.js`, `backend/functions/test/s3_callables_exports.test.js`

**Assessment:** Not duplicate implementations — single `onCall` definitions in `s3_storage.js`; deploy entry re-exports bound callables (lines 1311–1315). Audit 3 added export contract test only; **did not edit** `index.js` or `s3_storage.js` in this pass.

**Evidence:** `node --test test/s3_callables_exports.test.js` → **1 pass** (~3s load).

**Limitation:** SEC-10 production deploy list not re-verified on Firebase console (Audit 1 scope).

---

## CQ-02 — Large files

| File | Lines | Notes |
|------|-------|--------|
| `backend/functions/cross_role_sync.js` | 4294 | Cross-role sync + triggers — split by domain in future PR |
| `frontend/lib/features/shared/screens/patient_profile_screen.dart` | 2213 | UI mega-screen — extract sections incrementally |
| `backend/functions/s3_storage.js` | 1688 | Storage + authz — cohesive module |

**Action this audit:** None (risk > benefit for monolithic split without dedicated QA).

---

## CQ-03 — Configuration

**New:** `frontend/lib/core/config/app_web_urls.dart`  
**Consumers:** `doctor_invite_service.dart`, `ambulance_invite_service.dart`, `pharmacy_doctor_invite_service.dart`, `patient_profile_mock.dart`  
**Docs:** `docs/ENV_MATRIX.md` → `PUBLIC_WEB_ORIGIN`

**Developer usage:**

```bash
flutter run --dart-define=PUBLIC_WEB_ORIGIN=https://staging.doctornect.com
```

Default remains `https://doctornect.com` (production-safe).

---

## CQ-04 — Delete account

**New:** `frontend/lib/core/account/delete_account_flow.dart`  
**Screens updated:** doctor, patient, lab, pharmacy, ambulance profile  
**Behavior:** Unchanged — confirm dialog, `deleteMyAccount` callable, session clear, welcome route; errors via `userFacingDeleteAccountError`.

---

## CQ-05 / CQ-06

- **CQ-05:** Low comment debt confirmed; vendored PDF JS contains unrelated TODO strings — excluded.
- **CQ-06:** See `docs/audit/BRAND_NAMING_ALIASES.md`.

---

## Additional code-quality notes

- Removed **~250 lines** of duplicated delete-account UI across role profile screens.
- Support/legal `support@doctornect.com` strings in profile copy remain intentional (not moved to dart-define).

---

## Regression results

| Command | Result |
|---------|--------|
| `flutter analyze --no-pub` (frontend) | **No issues found** |
| `flutter test` app_web_urls, delete_account_flow, invite_deep_link | **14 pass** |
| `node --test test/s3_callables_exports.test.js` | **1 pass** |

---

## Git & separation

| Item | Value |
|------|--------|
| Branch at execution | `audit2/docker-ci-evidence` @ `081ae77` |
| Audit 3 commit | Isolated Flutter + docs + export test (see `git log`) |
| Audit 1 tree | `index.js`, `s3_storage.js`, CSP, infra — **not modified by Audit 3 CQ remediations** |
| Audit 2 commits | **Untouched** (`e9c42b7`, `081ae77`) |
| Push / merge / deploy | **None** |

---

## Completion criteria (Phase 12)

- [x] CQ-01 reviewed; SEC-10 boundary respected  
- [ ] CQ-02 split (deferred — documented)  
- [x] CQ-03 URLs centralized  
- [x] CQ-04 delete UX centralized  
- [x] CQ-05 reviewed  
- [x] CQ-06 documented  
- [x] Regression executed on changed areas  
- [x] Audit 3 documentation  
- [x] Audit 1/2 work not disturbed by CQ code changes  

**Mark Audit 3:** **PARTIALLY COMPLETE** until CQ-02 progressive refactors land.