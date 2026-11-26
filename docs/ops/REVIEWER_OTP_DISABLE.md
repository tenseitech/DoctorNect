> **Superseded (2026-11-25):** demo numbers, roles and routing are now fixed in code. The current reference is [docs/DEMO_ACCOUNTS.md](../DEMO_ACCOUNTS.md). REVIEW_*_PHONES / DEMO_PHONE_NUMBERS are ignored.

# Runbook: Disable Play Store reviewer fixed OTP (SEC-009)

**Purpose:** Close the **known-OTP + allowlisted phone** window used for Google Play / App Store review without deploying application code.  
**Scope:** Firebase Functions (`medibond-45fad` production, staging project when applicable).  
**Related:** `backend/functions/reviewer_otp_config.js`, `reviewer_secrets.js`, `assert_app_env.js` (`assertProductionReviewOtpDisabled`), SEC-009 in `docs/audit/SECURITY_AUDIT_2026-11-23.md`.

---

## When to run

| Trigger | Action |
|---------|--------|
| Play Console review **approved** or app **published** | **Disable within 24h** (target: same day). |
| `REVIEW_ACCESS_UNTIL` **passed** | System auto-fail-closes bypass; still run steps below to clear secrets. |
| Security incident / OTP leak suspected | **Immediate** disable + rotate `REVIEW_FIXED_OTP`. |
| Production cutover (`APP_ENV=production` on Functions) | Reviewer OTP must be **off** unless an active, time-boxed review window is deliberate (see guards). |

---

## How reviewer OTP works (operator mental model)

1. **`REVIEWER_OTP_ENABLED=true`** plus **`REVIEW_FIXED_OTP`** (Firebase **Secret**) and future **`REVIEW_ACCESS_UNTIL`** (ISO timestamp) enable bypass.
2. Allowlisted phones: `9999900001`–`9999900005` and/or `REVIEW_{ROLE}_PHONES` / `REVIEW_TEST_NUMBERS` env (see `reviewer_otp_config.js`).
3. Matching mobiles can complete OTP/login with the **fixed** secret value — **no MSG91 SMS** for that path when bypass applies.
4. **Production RDS:** demo/reviewer UIDs must not hit RDS PostgREST (`rds_demo_uid_guard`, demo routing). Reviewer bypass is still a **credential weakness** on Auth/Functions until disabled.
5. **`assert_app_env.js`:** With `APP_ENV=production` and reviewer **disabled**, plain-text `REVIEW_FIXED_OTP` in env is **rejected** at cold start (must use Secret Manager only).

---

## Disable procedure (no code change)

### Step 1 — Turn off the feature flag

**Firebase Console → Functions → Environment / params (or legacy config):**

```text
REVIEWER_OTP_ENABLED=false
```

Or remove the variable (treated as off).

**Verification (after deploy/restart):** Reviewer login with `9999900001` + fixed OTP must **not** succeed; normal MSG91 OTP path applies.

### Step 2 — Expire the time window (defense in depth)

Set a **past** timestamp (if your workflow still reads plain env):

```text
REVIEW_ACCESS_UNTIL=2020-01-01T00:00:00.000Z
```

With `REVIEWER_OTP_ENABLED=false`, `getReviewerConfig()` returns `null` regardless.

### Step 3 — Rotate the fixed OTP secret (recommended after Play approval)

```powershell
# From repo root; project = medibond-45fad for production
firebase functions:secrets:access REVIEW_FIXED_OTP --project medibond-45fad  # optional: confirm version exists
firebase functions:secrets:set REVIEW_FIXED_OTP --project medibond-45fad
# Enter a new random 6-digit value; store only in password manager until next review cycle.
```

Then **redeploy** Functions that bind `reviewer_secrets.js` / `defineSecret('REVIEW_FIXED_OTP')` so new revisions pick up the version.

### Step 4 — Clear phone allowlists (optional hygiene)

Unset or empty (staging only if you still need demo phones elsewhere):

```text
REVIEW_TEST_NUMBERS=
REVIEW_PATIENT_PHONES=
REVIEW_DOCTOR_PHONES=
… (other REVIEW_*_PHONES)
```

Do **not** confuse with `DEMO_PHONE_*` used for **demo data plane** routing — separate concern (`docs/ops/GATEWAY_DEMO_ROUTING_DEPLOY.md`).

### Step 5 — Redeploy Functions

```powershell
cd backend/functions
npm run deploy   # or your approved production deploy pipeline
```

**Verification checklist**

- [ ] `REVIEWER_OTP_ENABLED` is false in the **live** Functions runtime config.
- [ ] Play reviewer test numbers no longer accept fixed OTP.
- [ ] `node backend/functions/test/reviewer_login.test.js` still passes locally (regression guard).
- [ ] Production: `assertProductionReviewOtpDisabled` path satisfied (no plain `REVIEW_FIXED_OTP` in env when reviewer off).

---

## Re-enable (short window only)

Use only for a **new** Play review cycle:

1. Set `REVIEW_ACCESS_UNTIL` to **≤ 14 days** ahead (organizational max; shorten if possible).
2. `REVIEWER_OTP_ENABLED=true`
3. Set `REVIEW_FIXED_OTP` via **Secret Manager** only in production.
4. Confirm allowlisted numbers are **fictitious** (`99999xxxxx` pattern) and documented in internal ticket.
5. Calendar reminder **before** `REVIEW_ACCESS_UNTIL` to run **this disable runbook**.

---

## What we do **not** do here

- No Terraform / ECS / RDS changes.
- No change to MSG91 templates (see `docs/ops/MSG91_SMS_BUDGET_DESIGN.md` for spend controls).
- No disabling of **demo Supabase** plane (`DEMO_REAL_ROUTING_ENABLED`) — separate rollout doc.

---

## Evidence to attach (audit trail)

| Artifact | Example |
|----------|---------|
| Screenshot or CLI log | Firebase config showing `REVIEWER_OTP_ENABLED=false` |
| Secret version | New `REVIEW_FIXED_OTP` version id after rotation |
| Timestamp | Play approval email date + disable completion time |
| Ticket ID | Link to release / security change record |