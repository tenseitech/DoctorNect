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

**Gap (SEC-017):** An attacker can rotate **many distinct mobiles** and stay under per-number caps → unbounded MSG91 cost over a day.

---

## Design goals

1. **Hard ceiling** on MSG91 spend per calendar day (account + project).
2. **Fail closed** on OTP send when ceiling hit (user sees generic unavailable message — already patterned as `msg91UnavailableError`).
3. **Observable** — alert before hard stop (80% / 95%).
4. **No secret leakage** in logs (counts and hashes only).
5. **Staging** may use lower caps; **production** stricter.

---

## Layer 1 — MSG91 provider (mandatory)

| Action | Owner | Notes |
|--------|-------|-------|
| Enable **daily SMS credit / spend cap** on MSG91 account | Finance + eng | Platform-native; survives app bugs |
| Set **billing alert** at 50%, 80%, 100% of monthly budget | Finance | Email + SMS to on-call alias |
| Separate **API keys** for staging vs production | Eng | Staging key with minimal prepaid balance |
| Document **DLT template IDs** and route (Transactional) | Eng | Wrong route = higher cost / rejection |

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

### Counter

- **Key:** `sms:budget:{APP_ENV}:{YYYYMMDD}` in Redis (same cluster as OTP abuse limits).
- **Increment:** After MSG91 HTTP **2xx** on successful send (not on reviewer bypass, not on emulator test mode).
- **TTL:** 48h on key (covers TZ edge).

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
```

Loaded only in production via Firebase params / Secret Manager policy (same pattern as `assert_app_env.js`).

### Interaction with existing rate limits

1. Per-mobile / per-IP checks (**existing**).
2. **Then** daily budget check (**new**).
3. **Then** MSG91 HTTP call.

Reviewer OTP and `isOtpTestModeConfigured()` paths **must not** increment budget.

---

## Layer 4 — Abuse response playbook

| Symptom | Immediate action |
|---------|------------------|
| Budget 80% before noon IST | Enable WAF rate rules on Functions URL; review Cloudflare if fronted |
| Single IP dominating sends | Block IP at WAF; Redis IP ban extension |
| Many new mobiles | Temporary lower `SEND_MOBILE_MAX`; consider captcha / App Check enforcement |
| MSG91 key leak suspected | Rotate `MSG91_AUTH_KEY` in Secret Manager; revoke old key in MSG91 |

---

## Acceptance criteria (when code is built)

- [ ] Daily budget unit test: 2001st send rejected in production config mock.
- [ ] Reviewer bypass does not increment Redis budget key.
- [ ] Metrics dashboard shows `sms_daily_count` and `sms_daily_rejected`.
- [ ] Runbook section in `MANUAL_ACTIONS.md` for MSG91 cap change without deploy.

---

## References

- SEC-017 — `docs/audit/SECURITY_AUDIT_2026-11-23.md`
- Reviewer disable — `docs/ops/REVIEWER_OTP_DISABLE.md`
- Redis dependency — production OTP rate limits (`REDIS_HOST` in `assert_app_env.js`)