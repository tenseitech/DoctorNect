# SEC-017 — MSG91 SMS spend controls (design only)

**Status:** Design / operator runbook — **no code changes** in this document.  
**Context:** `backend/functions/registration_otp.js` enforces **per-IP** and **per-mobile** send limits; there is **no** project-wide daily SMS budget in application code today.

---

## Current controls (as implemented)

| Control | Value | Location |
|---------|-------|----------|
| Send per mobile | 5 / hour | `SEND_MOBILE_MAX`, `SEND_MOBILE_WINDOW_MS` |
| Send per IP | 10 / hour | `SEND_IP_MAX`, `SEND_IP_WINDOW_MS` |
| Verify per IP | 15 / hour | `VERIFY_IP_MAX` |
| Reviewer fixed OTP | Bypasses MSG91 for allowlisted phones | `reviewer_otp_config.js` — disable via `REVIEWER_OTP_DISABLE.md` |
| OTP verify lockout | 5 attempts / mobile (Redis) | `OTP_VERIFY_ATTEMPT_MAX` |

**`SEND_IP_MAX` / carrier NAT:** Many real users often share one **public IPv4** (mobile carrier CGNAT, office egress, institutional Wi‑Fi). A single abusive or high-volume client can exhaust the **per-IP** send bucket and cause **`resource-exhausted` for unrelated numbers** on that IP. Treat the IP limit as a **coarse** signal; do not tighten it in isolation without correlating IP-hash exhaustion with MSG91 spend.

**Gap (SEC-017):** An attacker can rotate **many distinct mobiles** and stay under per-number caps → unbounded MSG91 cost over a day.

---

## Design goals

1. **Hard ceiling** on MSG91 spend per calendar day (account + project), keyed to **IST** (see Layer 3).
2. **Fail closed** on OTP send when ceiling hit (user sees generic unavailable message — already patterned as `msg91UnavailableError`).
3. **Observable** — alert before hard stop (80% / 95%).
4. **No secret leakage** in logs (counts and hashes only).
5. **Staging** may use lower caps; **production** stricter.

**Primary abuse control (client → Functions):** **Firebase App Check** on OTP callables (attested app instances). Provider caps, Redis rate limits, and daily budget are **defense in depth** — not a substitute for App Check.

---

## Layer 1 — MSG91 provider (mandatory)

| Action | Owner | Notes |
|--------|-------|-------|
| Enable **daily SMS credit / spend cap** on MSG91 account | Finance + eng | Platform-native; survives app bugs |
| Set **billing alert** at 50%, 80%, 100% of monthly budget | Finance | Email + SMS to on-call alias |
| Separate **API keys** for staging vs production | Eng | Staging key with minimal prepaid balance |
| Document **DLT template IDs** and route (Transactional) | Wrong route = higher cost / rejection |

**Verification:** MSG91 dashboard → Reports → daily send count vs cap; screenshot monthly for audit folder.

---

## Layer 2 — AWS / Firebase monitoring (recommended)

| Signal | Source | Alert |
|--------|--------|-------|
| Cloud Functions **invocation count** on `sendOtp` / registration callables | Cloud Monitoring | Spike vs 7-day baseline |
| Cloud Functions **errors** `unavailable` + reason msg91 | Log-based metric | > N / 5 min |
| **Billing** Firebase Blaze + linked billing account | GCP Budget alert | Monthly OTP-related estimate |

**Budget example (illustrative — set with finance):**

- Production: **₹X / day** MSG91, **₹Y / month** hard stop at provider.
- Staging: **10%** of prod daily cap.

---

## Layer 3 — Application budget (future implementation sketch)

*Not implemented; specification for a later PR.*

### Counter and calendar day

- **Key:** `sms:budget:{APP_ENV}:{YYYYMMDD}` in Redis (same cluster as OTP abuse limits).
- **`YYYYMMDD` is the calendar day in `Asia/Kolkata` (IST),** not UTC. Reset semantics follow IST midnight; TTL on the key must cover IST boundary edge cases (see below).
- **TTL:** 48h on key (covers IST midnight rollover + minor clock skew).

### Reservation: atomic INCR-first, DECR on failure

Avoid “increment only after MSG91 2xx” under concurrency: two parallel sends can both pass a pre-check and double the provider bill. Use the same **atomic INCR + window TTL** pattern as `abuse_rate_limit.js`:

1. **Reserve** one unit: `INCR` the budget key (Lua or MULTI: INCR + PEXPIRE on first touch).
2. If `count > SMS_DAILY_BUDGET_MAX`: **`DECR`** (or conditional roll-back) to release the slot, reject with `unavailable` — **no MSG91 HTTP call**.
3. If `count <= max`: slot is reserved; proceed to MSG91.
4. On **MSG91 failure** (non-2xx, timeout, network error): **`DECR`** the budget key to release the reservation (clamp so the key does not go negative).
5. On **MSG91 2xx:** leave the counter as-is (reservation becomes a committed send).

Reviewer OTP and `isOtpTestModeConfigured()` paths **must not** reserve or increment the budget key.

### Redis unavailable or slow

Align with existing send rate limits (`abuse_rate_limit` / production Redis requirement):

| Condition | Behavior |
|-----------|----------|
| Redis connection error, timeout, or eval failure while reserving budget | **Fail closed** — reject OTP send with generic `unavailable` (do **not** call MSG91). |
| Rationale | A bypass when Redis is down would remove both rate limits and daily ceiling during the exact window attackers probe. |
| Ops signal | Log/metric `sms_budget_redis_fail_closed` (count only); correlate with ElastiCache / MemoryDB health and OTP error rate. |

### Budget exhausted — real-user lockout risk

When the daily cap is reached, **every** non-bypass send fails until the **next IST calendar day** (or an operator raises the cap). That is intentional for spend protection but creates **product risk**:

- Legitimate peaks (campaign, recovery after outage, holiday traffic) can hit the cap before MSG91 dashboard alerts.
- Users see the same generic SMS-unavailable message as abuse or provider outage — support cannot distinguish without internal metrics.

**Tuning / runbook:**

- Set `SMS_DAILY_BUDGET_MAX` from baseline: typical daily OTP sends (p95) + headroom; revisit after DAU changes.
- Treat 80% / 95% soft thresholds as **action** triggers (finance + on-call), not only logs.
- Prefer **raising cap via config** (Firebase params) over disabling the feature; keep MSG91 provider daily cap as the ultimate backstop.
- Document temporary cap bumps in `MANUAL_ACTIONS.md` when implemented.

### Limits (proposed defaults)

| Environment | Daily max SMS sends | Action at 100% |
|-------------|---------------------|----------------|
| `production` | 2,000 (tune from baseline traffic) | Reject new sends with `unavailable` |
| `staging` | 200 | Same |
| `development` | 0 (MSG91 disabled / test mode) | N/A |

### Soft thresholds

- **80%:** `security_logger` WARN + optional Slack webhook (no PII).
- **95%:** PAGE on-call (SMS pumping suspected).

### Config surface

```text
SMS_DAILY_BUDGET_ENABLED=true
SMS_DAILY_BUDGET_MAX=2000
SMS_DAILY_BUDGET_SOFT_PCT=80
SMS_DAILY_BUDGET_TZ=Asia/Kolkata
```

Loaded only in production via Firebase params / Secret Manager policy (same pattern as `assert_app_env.js`).

### Interaction with existing rate limits

1. **Firebase App Check** verification on the callable (primary client trust boundary).
2. Per-mobile / per-IP checks (**existing** Redis buckets).
3. **Daily budget reserve** (INCR-first, fail closed if Redis unavailable).
4. **Then** MSG91 HTTP call (DECR budget reservation on failure).

---

## Layer 4 — Abuse response playbook

| Symptom | Immediate action |
|---------|------------------|
| Budget 80% before noon IST | Confirm **App Check** enforcement on OTP callables; review send metrics by environment; coordinate with finance on MSG91 dashboard cap |
| Single IP dominating sends | Redis IP ban extension; tighten **App Check** / client attestation — do not rely on IP limit alone (NAT collateral) |
| Many new mobiles | **Enforce App Check** (primary); temporarily lower `SEND_MOBILE_MAX` if needed |
| MSG91 key leak suspected | Rotate `MSG91_AUTH_KEY` in Secret Manager; revoke old key in MSG91 |

**Note:** OTP callables are invoked via the **Firebase Functions SDK**, not a separate HTTP Functions URL fronted for WAF. Edge WAF rules do not replace **App Check** on callables.

---

## Acceptance criteria (when code is built)

- [ ] Daily budget unit test: 2001st send rejected in production config mock.
- [ ] Reviewer bypass does not touch budget key.
- [ ] Concurrent send test: INCR-first prevents over-cap MSG91 calls; failed MSG91 path DECRs reservation.
- [ ] Redis-down test: send rejected fail-closed without MSG91 call.
- [ ] Budget key rolls on IST midnight (test with injected clock or tz helper).
- [ ] Metrics dashboard shows `sms_daily_count` and `sms_daily_rejected`.
- [ ] Runbook section in `MANUAL_ACTIONS.md` for MSG91 cap change without deploy.

---

## References

- SEC-017 — `docs/audit/SECURITY_AUDIT_2026-11-23.md`
- Reviewer disable — `docs/ops/REVIEWER_OTP_DISABLE.md`
- Redis dependency — production OTP rate limits (`REDIS_HOST` in `assert_app_env.js`)