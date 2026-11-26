# Audit 6 — Reliability & degradation matrix (REL-07 / REL-09)

**Verification:** Static code review + local unit tests unless noted.

| Scenario | Critical workflows | Expected UX | Retry | Duplicate risk | Recovery | Verified |
|----------|-------------------|-------------|-------|----------------|----------|----------|
| Supabase / Postgres down | Booking, RX, lab | User-facing error via classifier/guards | Transient retry (bounded) on reads/helpers | Guard reduces double-submit client-side | Retry when online | Partial (tests) |
| Gateway down | All REST/RPC | Flutter errors / maintenance guards | Transient retry classifies network | Same | Reconnect | Not runtime |
| Redis unavailable | Gateway rate limit | Falls back per `rate_limit_factory` (in-memory) | N/A | Low | Auto when Redis up | Not runtime |
| Firebase Auth down | Login / OTP | Auth screens show errors | No blind retry on 401 | N/A | User retry login | Not runtime |
| Realtime disconnected | Live lists | Stale until poll/stream recover | Bootstrap debounced `setAuth` | Duplicate events coalesced (Audit 5) | Token refresh + reconnect | Partial |
| Token refresh failure | Supabase writes | Write guard / errors | No infinite retry | Low | Re-login | Partial |
| Network offline | All mutations | Actionable messages (`describeUserFacingError`) | Bounded transient retry | In-flight guard | User retry | Partial |
| Slow network | Uploads / booking | Timeouts (gateway proxy 15s, DLQ 8s) | Backoff | Medium without server keys | User retry | Static |
| Gateway 429 | API calls | Rate limit response | No automatic client storm | Low | Backoff / wait | Static |
| Backend 5xx | RPC | Transient classifier retries (helpers) | Bounded | Medium on non-idempotent RPC | User retry | Partial |
| Permission denied | Writes | Fail fast, no retry | No | N/A | Fix auth/role | Static |
| Cross-role sync failure | Data consistency | DLQ row + Firestore backup path | Transient-only sync retry | DLQ dedupe by entity | Ops replay DLQ | Not runtime |
| DLQ unreachable | Sync | Logged CRITICAL + local pool/Firestore | DLQ POST 8s timeout | N/A | Ops intervention | Static |
| Notification failure | In-app push | Often non-blocking side effect | Varies | notification_id upsert | Resync | Partial |
| S3 presign/confirm fail | Lab/doctor uploads | User error; confirm idempotent | Limited | Low on confirm | Retry upload | Tested (confirm) |
| App killed mid-mutation | Booking/RX | No durable offline queue | N/A | Possible duplicate without server key | User must verify state | **Not verified** |

**Security:** Degraded paths must not bypass authorization (no fail-open).