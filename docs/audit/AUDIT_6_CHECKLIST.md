# Audit 6 checklist

**Branch:** `audit6/reliability-resilience`  
**Report:** `AUDIT_6_RELIABILITY_REPORT.md`

| Item | Status |
|------|--------|
| Git baseline inspected | Done |
| Audit 1–5 preservation | Done |
| Audit 4 ON HOLD | Verified — no Audit 4 commit |
| Network failure audit | Done (static + DLQ timeout) |
| Retry audit / fixes | Done (`transient_error`, sync infra) |
| Timeout audit | DLQ 8s; proxy 15s documented |
| Idempotency | `InFlightGuard` library; RPC keys pending |
| Concurrency | In-flight guard tests |
| Realtime reliability | Bootstrap debounce + cleanup |
| Background tasks | Sync retry classification |
| Error handling | Classifier + no blind retry |
| Graceful degradation | Static matrix in report |
| Logging / correlation | `request_id` field ready |
| Gateway server wiring | **Blocked** — mixed Audit 4 tree |
| Regression tests | 10 tests pass |
| Documentation | Done |
| Git commit | `e8435ea` |
| Push `audit6/reliability-resilience` | Done |
| `CODEBASE_AUDIT_REPORT.md` §23 | Local only (mixed §21–22 unstaged) |