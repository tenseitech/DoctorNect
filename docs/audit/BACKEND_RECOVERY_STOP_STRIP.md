# Backend Firestore strip — STOP / recovery (2026-11-15)

## 1. Checkpoint

| Item | Value |
|------|--------|
| Branch | `fix/pre-accept-gate-lab-auth` (ahead of `origin` by 2 commits) |
| Last **documented green** backend suite | **544 pass / 0 fail / 562 tests** (18 skipped) — `docs/audit/npm_test_verify_suite.txt` (~42s on prior host) |
| Baseline git commit (suite proof not tied to a single SHA) | `00059d2` — `HEAD` before this recovery session’s working-tree edits |
| Strip regression (reverted) | **503 pass / 43 fail**, ~81 min — `docs/audit/_npm_test_run1.txt` (Redis ECONNREFUSED spam, gutted handlers) |
| **Recovered** | **545 pass / 0 fail / 563 tests** (18 skipped), **~31s** — `docs/audit/npm_test_recover_green_final.txt` |

### Backend-only changes vs `HEAD` (committed + staged intent)

| File | Change |
|------|--------|
| `backend/functions/test/setup_env.js` | Strip inherited `RUNTIME_DOCUMENT_DB_FORBIDDEN` from shell `.env` |
| `backend/functions/src/db/assert_app_env.js` | Production cutover boot checks (not wired in `index.js` at HEAD) |
| `backend/functions/admin_platform_actions.js` | Minor trim |
| `backend/functions/user_id_bridge.js` | Minor |
| `.env.example` | `FIRESTORE_TRIGGER_REGION`, `FORCE_REDIS_INTEGRATION` (env-parity) |

**Reverted to `HEAD` for green:** `legacy_db.js`, `firestore_forbidden_guard.js`, `backend/firestore.rules`, `index.js` `db()` → `getLegacyFirestoreDb()`.

**Strip artifacts left untracked (do not deploy):** `runtime_app_db.js`, `test/lib/cross_role_sync_bridge.js`, extra OTP/pg tests.

**Not resumed:** deleting `cross_role_sync.js`, Firestore-free `promoted_ads.js` / `appointment_slots.js`, or `RUNTIME_DOCUMENT_DB_FORBIDDEN` in `legacy_db`.

---

## 2. Triage — 43 failures (strip run)

Root causes cluster into **five** buckets (full per-test names in `docs/audit/_npm_test_run1.txt` + `npm_test_recover_after_revert.txt`).

| File | Tests (summary) | Release-critical? | Cause | Resolution |
|------|-----------------|-------------------|-------|------------|
| `test/promoted_ads_verification.test.js` | verifyRazorpayPayment, createRazorpayOrder, webhook race (~14) | **Yes** (payments) | Strip: `getLegacyFirestoreDb()` null; inherited `RUNTIME_DOCUMENT_DB_FORBIDDEN=1` | Revert handlers + strip env key in `setup_env.js` |
| `test/appointment_slots*.test.js` | concurrent book, cancel, reschedule, token (~13) | **Yes** (booking) | Gutched `appointment_slots.js` / deleted Firestore mock paths | `git checkout HEAD -- appointment_slots.js` |
| `test/registration_otp.test.js` | lockout, Redis mirror, concurrent verify (~18) | **Yes** (auth) | Partial OTP rewrite + Redis connecting to `:6390` in default suite | Revert `registration_otp.js`; keep integration test behind `FORCE_REDIS_INTEGRATION` |
| `test/cross_role_sync.test.js`, `doctor_sync`, `ambulance_sync`, `pharmacy_lab_sync` | suite + subtests (~8 files) | Medium | Deleted/moved `cross_role_sync.js`, bridge in `test/lib` | Revert runtime files; remove strip-only test requires |
| `test/env_parity.test.js` | ENV-01 | Medium | Undocumented env keys from strip | Document keys in `.env.example` |
| `test/firestore_rules_regex.test.js` | deny-all rules | Low | Accidental delete `backend/firestore.rules` | Restore from `HEAD` |
| `test/index_exports.test.js` | Postgres-only bridge export | Low | Strip changed `index.js` exports | Revert `index.js` |
| `test/backfill_users_to_supabase.test.js` | (file-level) | Low | Timeout/hang during strip run | Green after revert (~30s suite) |

**Hangs:** default `npm test` without `--test-timeout` + **live Redis** attempts (`127.0.0.1:6390`) during strip OTP work → ~81 min. **Mitigation:** `node --test --test-timeout=30000` + noop Redis in `setup_env.js` (HEAD behavior).

**Deleted tests this session:** none (strip had proposed deletions; **release-critical suites kept**).

---

## 3. Fix summary

1. **Reverted** backend strip mutations on runtime JS (handlers, guards, `index.js` db helper).
2. **`setup_env.js`:** delete `RUNTIME_DOCUMENT_DB_FORBIDDEN` from inherited env (shell `.env` had `=1`, which broke Razorpay unit mocks even when tests set `FIRESTORE_FORBIDDEN=0`).
3. **Restored** `backend/firestore.rules` (deny-all).
4. **`.env.example`:** `FIRESTORE_TRIGGER_REGION`, `FORCE_REDIS_INTEGRATION` for `check_env_parity`.
5. **No** loosening of OTP / Razorpay / booking / delete-account assertions.

---

## 4. Suite target

| Metric | Target | Actual |
|--------|--------|--------|
| Pass / fail | 0 fail (18 emulator skips OK) | **545 / 0** |
| Duration | < 5 min | **~31s** |
| Evidence | — | `docs/audit/npm_test_recover_green_final.txt` |

**Slow / hanging (historical):** full suite during strip without timeout; `otp_redis_integration.test.js` when Redis down (skipped unless `FORCE_REDIS_INTEGRATION=1`); emulator suites (18 skipped).

---

## 5. Backend Firestore grep (141 lines) — post-release classification

**Not a release blocker** when `FIRESTORE_FORBIDDEN=1` + `legacy_db` null + guard throws on raw Admin SDK.

| Classification | Lines (inventory) | Meaning |
|----------------|------------------:|---------|
| **NOT-REACHABLE (prod)** | ~80 `LIVE_IF_FLAG_OFF` + 28 `GUARD` | Code exists but `getLegacyFirestoreDb()` → `null` or guard throws before I/O in prod |
| **POST-RELEASE cleanup** | ~96 comments/strings, ~88 `DEAD_OR_LEGACY`, 12 imports | Rename comments, drop dead branches, emulator scripts |
| **TEST-ONLY** | `test/**`, `test/lib/**`, rules emulator scripts | Emulator / mock paths |

### File-wise (grep line count, `BACKEND_RUNTIME_FIRESTORE_GREP.txt`)

| File | Lines | Prod reachability |
|------|------:|-------------------|
| `cross_role_sync.js` | 48 | NOT-REACHABLE (not exported post-cutover; guard) |
| `appointment_slots.js` | 28 | NOT-REACHABLE (callable uses PG RPC when primary) |
| `promoted_ads.js` | 18 | **Partial** — Postgres Razorpay path live; legacy Firestore branch NOT-REACHABLE if forbidden |
| `delete_my_account.js` | 12 | NOT-REACHABLE (Supabase cleanup primary) |
| `s3_storage.js` | 11 | NOT-REACHABLE fallback |
| `seed_demo_accounts.js` | 8 | Script only |
| `review_public_sync.js` | 7 | Legacy sync |
| `index.js` | 6 | Imports + comments; callables use `getLegacyFirestoreDb()` |
| Others (≤5 each) | 24 | Mostly guard/comments |

**REACHABLE prod I/O before guard:** none identified in inventory when `FIRESTORE_FORBIDDEN=1` (see `firestore_forbidden_guard.js` hooks).

---

## 6. Pending work — priority

| Item | Priority |
|------|----------|
| Production AAB full Gradle on operator machine | **Release-blocking** |
| Staging migrations `20261115000001`–`003` + live write smoke | **Release-blocking** |
| Firebase prod env (`APP_ENV=production`, `FIRESTORE_FORBIDDEN=1`) materialized on deploy | **Release-blocking** |
| OTP Lua parallel lockout (re-apply on green `registration_otp.js` + Redis `:6390` proof) | **Release-blocking** (if not already on deployed functions) |
| Flutter “restored” widget/integration tests beyond 677 unit tests | Post-release |
| Degraded-state UI (offline / gateway errors) | Post-release |
| Firebase Storage asset inventory + client URL migration | Post-release |
| Backend Firestore grep → 0 / handler migration | Post-release (guard sufficient for cutover) |