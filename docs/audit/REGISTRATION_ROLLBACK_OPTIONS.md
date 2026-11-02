# Registration rollback options (design notes — not implemented)

## Current approach (implemented)

**Server callable `cleanupPendingRegistration`:** authenticated caller only; service role deletes fresh orphan `public.users` / role rows then Auth user under shared guards. Client invokes the callable before local Auth delete on registration failure paths.

## Alternative: reclaim-on-retry (not implemented)

**Idea:** On a new registration attempt with the same mobile or email, detect an existing **fresh orphan** row owned by a **different** Firebase UID (or stale Auth user) and **reassign or delete** it automatically so the retry succeeds without a explicit cleanup callable.

### Why it is risky

| Risk | Detail |
|------|--------|
| **Enumeration** | Different API responses or timing (“reclaimed” vs “duplicate”) can leak whether a mobile/email exists in the system. |
| **Wrong-owner reclaim** | Race: two devices registering the same number; reclaim could delete the wrong in-progress attempt or a legitimate second factor flow. |
| **Cross-UID trust** | Without strict proof that the caller owns the mobile (OTP session bound to the orphan row), reclaim becomes a weak form of account takeover. |
| **Audit / support** | Harder to explain partial state (“why did my half-created account vanish?”) without explicit user-initiated cleanup. |

### Safer variant (still not chosen)

- Reclaim only when **OTP session ID** matches the orphan row’s pending session and both are **&lt; 10 minutes** old, and response is always `{ ok, conflict }` with **no** extra hints — still requires careful privacy review.

**Recommendation:** keep explicit **caller-initiated cleanup** via `cleanupPendingRegistration` and client fallback Auth delete only when the callable is unreachable.
