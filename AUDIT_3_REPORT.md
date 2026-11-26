# Audit 3 — Code Quality, Remediation & Regression

**Date:** 2026-11-26 (final pass)  
**Branch:** `audit3/code-quality`  
**Scope:** CQ-01 … CQ-06 per `CODEBASE_AUDIT_REPORT.md` § AUDIT 3  
**Overall status:** **COMPLETE** (accepted debt: sync orchestrators remain in `cross_role_sync.js`; patient profile UI ~2.2k LOC)

---

## Executive summary

Audit 3 verified S3 deploy wiring (CQ-01), split `cross_role_sync.js` into focused modules (CQ-02), centralized Flutter web URLs and delete-account UX (CQ-03/04), confirmed low TODO debt (CQ-05), and documented Medibond/DoctorNect aliases (CQ-06). Regression: **71** Functions sync tests, **14** Flutter tests, analyzer clean. Audit 1 **NOT CLOSED**; Audit 2 **OPEN**. No push, merge to `main`, or deploy.

---

## CQ status table

| ID | Original issue | Remediation | Tests | Status |
|----|----------------|-------------|-------|--------|
| CQ-01 | S3 callables deploy wiring | Verified `index.js` re-exports; `s3_callables_exports.test.js` | 1 pass | **VERIFIED** (SEC-10 / Audit 1) |
| CQ-02 | `cross_role_sync.js` ~4.3k LOC | Extracted infra, coerce, payloads, pg modules | 70 sync + C.10 pass | **REFACTORED** (orchestration ~3530 LOC remains) |
| CQ-03 | Hardcoded invite URLs | `AppWebUrls` + `PUBLIC_WEB_ORIGIN`; lab invite sheet + Telegram default | 14 pass | **FIXED** |
| CQ-04 | Duplicated delete-account UX | `delete_account_flow.dart` | 3 pass | **FIXED** |
| CQ-05 | TODO debt | Grep: none in `frontend/lib`, functions `*.js` | — | **INFO** |
| CQ-06 | Brand naming | `BRAND_NAMING_ALIASES.md` | — | **DOCUMENTED** |

---

## CQ-02 — `cross_role_sync.js` refactor

### Before / after (lines)

| Module | Lines | Responsibility |
|--------|------:|----------------|
| `cross_role_sync.js` (before) | **4294** | Monolith |
| `cross_role_sync.js` (after) | **3530** | Firestore→Supabase sync orchestration (per-entity handlers) |
| `cross_role_sync_payloads.js` | **568** | Payload builders, role normalization, appointment origin |
| `cross_role_sync_coerce.js` | **85** | Types, timestamps, UUID validation |
| `cross_role_sync_infra.js` | **100** | Supabase config, retry, DLQ |
| `cross_role_sync_pg.js` | **74** | PG merge / compare-and-skip helpers |
| **Total maintained** | **4257** | Same behavior; clearer boundaries |

### Architectural rationale

- **No behavioral change** — public `module.exports` from `cross_role_sync.js` unchanged for triggers and tests.
- **Extraction by concern** — configuration/DLQ, coercion, REST payload mapping, and PG utilities separated from long sync handlers.
- **Future work** — split per-domain sync handlers (doctor/pharmacy/lab/ambulance/user) when paired with narrower integration tests.

### Evidence

```text
node --test test/cross_role_sync.test.js test/doctor_sync.test.js \
  test/pharmacy_lab_sync.test.js test/ambulance_sync.test.js \
  test/user_identity_bridge.test.js test/s3_callables_exports.test.js
# 71 pass, 0 fail
```

C.10 contract test updated to read `cross_role_sync_infra.js` for `APP_ENV` / gateway env vars (config moved, not removed).

---

## CQ-01

Unchanged from commit `2bbe4b9`. Audit 3 did not edit Audit 1 `index.js` / `s3_storage.js` in the final pass.

---

## CQ-03 / CQ-04

- **Final pass:** `LabDoctorInviteService` and `ExternalLauncher.shareViaTelegram` default URL use `AppWebUrls`.
- **Intentionally fixed:** legal copy, auth placeholder emails (`@auth.doctornect.com`), support strings in UI.

---

## Regression (final pass)

| Command | Result |
|---------|--------|
| `flutter analyze --no-pub` | No issues |
| `flutter test` (app_web_urls, delete_account, invite_deep_link) | **14 pass** |
| Functions sync + S3 export tests (above) | **71 pass** |

---

## Git

| Item | Value |
|------|--------|
| Branch | `audit3/code-quality` |
| Prior commit | `2bbe4b9` — Flutter CQ-03/04/docs |
| Final pass commit | (see `git log -1`) |
| Audit 1 / 2 | Uncommitted Audit 1 tree preserved; Audit 2 commits untouched |
| Push / merge / deploy | **None** |

---

## Accepted technical debt

1. `cross_role_sync.js` sync handlers (~3530 LOC) — next split by domain.
2. `patient_profile_screen.dart` (~2213 LOC) — below 4k threshold; incremental UI extraction.
3. User-facing `support@doctornect.com` literals in legal/profile copy (brand constants, not env).

---

## Completion criteria

All CQ items remediated or documented; regression green on touched areas; Audit 1 SEC-10 not claimed closed.

**Audit 3:** **COMPLETE** with debt above.