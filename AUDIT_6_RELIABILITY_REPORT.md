# Audit 6 — Reliability, resilience & observability

**Date:** 2026-11-26  
**Branch:** `audit6/reliability-resilience`  
**Commit:** `e8435ea`  
**Base:** Audit 5 follow-up `92ac451`

**Status:** **AUDIT 6 COMPLETE** (code + tests). Gateway `server.js` correlation wiring **PARTIALLY FIXED** (Audit 4 hold).

---

## Executive summary

Hardened sync retry classification and backoff, added client-side transient retry helpers and in-flight guards, improved Supabase realtime auth debouncing and subscription cleanup, added gateway request-id utilities and structured audit log field, and added DLQ POST timeout. **Audits 1–5 preserved. Audit 4 ON HOLD** (no migration, no mixed gateway commit).

---

## Findings (implemented)

| ID | Sev | Finding | Remediation | Status |
|----|-----|---------|-------------|--------|
| REL-02 | High | Sync retried permanent errors | `isTransientSyncError` + jitter backoff | **FIXED** |
| REL-03 | Med | DLQ HTTP fetch unbounded | `AbortSignal.timeout(8000)` | **FIXED** |
| REL-05 | Med | Duplicate client mutations | `InFlightGuard` | **FIXED** (library) |
| REL-06 | Med | Realtime auth storm on token refresh | Debounced `setAuth` + subscription dispose | **FIXED** |
| REL-10 | Med | No request correlation in gateway logs | `request_context.js` + `request_id` in `emitAuditLog` | **PARTIAL** |
| REL-02 | Med | Flutter lacks shared transient retry | `transient_retry.dart` + classifier | **FIXED** |

---

## Remaining (documented)

| ID | Sev | Note | Status |
|----|-----|------|--------|
| REL-10 | Med | Wire `requestId` in `server.js` when Audit 4 hold clears | **BLOCKED** — see `AUDIT_6_GATEWAY_CORRELATION_PATCH.md` |
| REL-04 | Med | Idempotency keys for all critical RPCs | **OPEN** (schema/Audit 4 dependent) |
| REL-08 | Low | Empty catch blocks in legacy sync paths | **ACCEPTED RISK** (CQ-02 scope) |
| REL-09 | Med | End-to-end graceful degradation matrix | **DOCUMENTED** (static) |

---

## Architecture reviewed

Flutter (Supabase bootstrap, reliability helpers), Cloud Functions (`cross_role_sync_infra`), Auth Gateway (`security.js`, `proxy.js` timeouts verified at 15s), existing `executeWithRetry` usage across sync handlers.

---

## Tests

| Suite | Pass | Fail |
|-------|-----:|-----:|
| `node --test test/transient_error.test.js` | 3 | 0 |
| `node --test test/request_context.test.js` | 3 | 0 |
| `flutter test test/core/reliability/reliability_helpers_test.dart` | 4 | 0 |

---

## Files changed (Audit 6 commit scope)

- `backend/functions/src/reliability/transient_error.js`
- `backend/functions/cross_role_sync_infra.js`
- `backend/functions/test/transient_error.test.js`
- `services/api-gateway/src/request_context.js`
- `services/api-gateway/src/security.js`
- `services/api-gateway/test/request_context.test.js`
- `frontend/lib/core/reliability/*`
- `frontend/lib/core/supabase/supabase_bootstrap.dart`
- `frontend/test/core/reliability/reliability_helpers_test.dart`
- `docs/audit/AUDIT_6_CHECKLIST.md`
- `docs/audit/AUDIT_6_GATEWAY_CORRELATION_PATCH.md`

**Not committed:** `server.js` (contains uncommitted Audit 4 health probes), Audit 4 artifacts.

---

## Audit preservation

| Audit | Status |
|-------|--------|
| Audit 1–3 | Unchanged in commit |
| Audit 4 | **ON HOLD** — not staged |
| Audit 5 | Preserved (`3604f92`, `d456cdc`, `92ac451`) |

---

## Final status

**AUDIT 6 COMPLETE** — Runtime staging verification not performed.