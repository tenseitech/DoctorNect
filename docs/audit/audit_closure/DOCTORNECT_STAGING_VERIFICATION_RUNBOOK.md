# DoctorNect — Staging Verification Runbook (Audits 1–9 closure)

**Purpose:** Operator steps for verifications that cannot run without staging credentials, AWS, Docker locally, or physical devices.  
**Policy:** No production users, no production deploy, no Audit 4 migrations while Audit 4 is ON HOLD.

---

## Prerequisites

| Check | Command | Expected |
|-------|---------|----------|
| Local env parity | `node scripts/check_env_parity.js` | Exit 0 |
| Staging prereq scan | `node scripts/security/audit1_staging_prereq_check.js` | Exit 0 when vars set (else documents missing keys) |
| Local closure summary | `node scripts/audit_closure/verify_local_closure.js` | Exit 0 when env parity passes |

Copy `.env.example` → gitignored `.env`. Fill **staging-only** values. Never commit `.env`.

### Required optional variables (commented in `.env.example`)

- `AUDIT1_STAGING_GATEWAY_URL`
- `AUDIT1_STAGING_HOSTING_URL`
- `AUDIT1_FIREBASE_PROJECT_ID`, `AUDIT1_FIREBASE_WEB_API_KEY`
- `AUDIT1_TEST_FIREBASE_EMAIL`, `AUDIT1_TEST_FIREBASE_PASSWORD` (dedicated test user only)
- `GOOGLE_APPLICATION_CREDENTIALS` (staging ADC file path, file must exist)

---

## SEC-04 — Token revocation → Gateway 401

**Safety:** Dedicated staging Firebase user only. Never revoke production accounts.

1. Run prereq: `node scripts/security/audit1_staging_prereq_check.js` → `SEC_04.ready: true`.
2. Sign in test user; obtain ID token (Firebase REST or client SDK against **staging** project).
3. Call protected gateway route with `Authorization: Bearer <token>` → expect 200/expected success.
4. `revokeRefreshTokens` for test UID via Admin SDK (staging project).
5. Repeat protected call → expect **401** with no sensitive body leakage.
6. Capture: request IDs, HTTP status, timestamp (no token in logs).

**Failure:** Missing gateway URL or ADC → classify **BLOCKED**, do not weaken `FIREBASE_REVOCATION_CHECK`.

---

## SEC-07 — Hosted Flutter CSP

1. Set `AUDIT1_STAGING_HOSTING_URL` to staging Hosting URL (not production unless designated staging).
2. Open URL in browser DevTools → Network → document response headers.
3. Verify `Content-Security-Policy` / `connect-src` allows Supabase, gateway, Firebase as documented.
4. Load app; confirm no critical CSP console errors; login shell renders.

**Failure:** No hosting URL → **PENDING OPERATOR**.

---

## SEC-08 — ECS multi-task Redis rate limit

**Requires:** AWS CLI, staging ECS, shared `RATE_LIMIT_REDIS_URL` on gateway tasks.

1. Confirm ≥2 gateway tasks on staging ECS.
2. Issue burst requests exceeding per-IP limit from single client.
3. Expect **429** consistently regardless of which task serves requests.
4. Optional: stop Redis briefly on **staging only** — expect documented fail-safe (not production).

---

## REL-10 — Request/log correlation (Audit 6)

1. `curl -v` staging gateway with optional `X-Request-Id: audit-closure-test-1`.
2. Note `x-request-id` response header.
3. In staging log sink, search same ID within 5 minutes.
4. Confirm redaction (no patient PHI, no bearer tokens).

---

## Audit 7 — Synthetic probes

```bash
# Set non-production gateway base URL only
node scripts/ops/synthetic_gateway_probe.js
```

Verify JSON output: healthy/degraded semantics match `AUDIT_7_FINAL_OPERATIONAL_VERIFICATION_REPORT.md`.

---

## Audit 8 — Staging E2E (manual matrix)

| Flow | Staging test account | Pass criteria |
|------|---------------------|---------------|
| OTP login | Dedicated role phones | Dashboard loads |
| Book appointment | Patient test | Confirmation without duplicate charge |
| Lab booking | Patient test | Order visible in lab role |
| Prescription view | Doctor test | PDF/preview opens |

Document screenshots + request IDs only.

---

## Audit 9 — Device accessibility

| Platform | Tool | Flows |
|----------|------|-------|
| Android | TalkBack | Auth back, booking, notifications |
| iOS | VoiceOver | Same |
| Web | Keyboard only | Auth layout, modals |

Record pass/fail per screen; attach to closure checklist.

---

## Cleanup

- Delete temporary test appointments/orders created on staging if policy requires.
- Do not leave test tokens in shell history.

## Prohibited

- Production migrate/deploy
- Audit 4 migration `20261126000001_*`
- Force push / `git clean`
- Disabling revocation or CSP for convenience