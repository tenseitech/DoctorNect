# Login hotfix deploy plan (local prep only — not executed)

**Goal:** Ship additive `exists` / `role` on **post-OTP** responses only (`verifyUserRegistrationOtp`, `completeMobileOtpLogin`) without redeploying the full `chore/dedupe-structure-audit` branch (22 Firestore triggers removed vs Oct-era exports).

**Hotfix base commit (git):** `9883f00` — Oct 24 functions-relevant tip per `docs/audit/DEPLOY_HASH_COHORT.md` (deploy proxy for STALE_REF cohort alongside `fb8e2e13` era).

**Prepared worktree:** `../doctor-hotfix` (detached HEAD `9883f00`) with **only** `backend/functions/registration_otp.js` patched (+ local copy of login OTP tests).

**Urgency:** **Not urgent.** The chore-branch **frontend already works** against the **old backend** via legacy `check()` fallback. Schedule backend hotfix together with the **frontend app release** that consumes post-OTP `exists`/`role`.

**Env:** [LOGIN_HOTFIX_ENV_PLAN.md](./LOGIN_HOTFIX_ENV_PLAN.md) — names only, MISSING-VALUE gaps vs today's `.env`.

**Source proof:** [DEPLOYED_SOURCE_CHECK.md](./DEPLOYED_SOURCE_CHECK.md) — operator-run `gcloud` download + hash compare (not run by agent).

---

## Worktree full `npm test` (9883f00 era, isolated)

| State | pass | fail | skip | total |
|-------|-----:|-----:|-----:|------:|
| Clean `9883f00` (no patch) | 443 | 6 | 18 | 467 |
| Additive post-OTP patch only | 445 | 4 | 18 | 467 |

Same test count; **+2 passes**, **−2 failures** (OTP/login scenario tests). Remaining failures are pre-existing at Oct 24 tip (not introduced by patch).

---

## Verify deployed code baseline

| Check | Command / expectation |
|-------|------------------------|
| Git object at Oct 24 tip | `git cat-file -t 9883f00` → commit |
| `registration_otp.js` blob at deploy tip | `git show 9883f00:backend/functions/registration_otp.js \| git hash-object --stdin` → **`7805656b85bbb065f13ea446a2d5d5f461686b1c`** |
| Chore branch blob (do **not** deploy whole tree) | `git hash-object backend/functions/registration_otp.js` on `chore/dedupe-structure-audit` → different hash |
| Cloud Run provenance | Compare revision build id / source SHA in console to `9883f00` (operator) |

**Confidence:** **High** that `9883f00` matches **2026-10-24T06:18Z** functions slice for OTP modules **if** production was built from the Oct 24 redeploy line documented in `DEPLOY_HASH_COHORT.md`. **Medium** without a live `gcloud run revisions describe` source hash. **Not** the Oct 31 postgres-only slice (`4dfae67`).

---

## Hotfix diff summary (`9883f00` → worktree patch)

| Metric | Value |
|--------|------:|
| File | `backend/functions/registration_otp.js` only |
| Approx. lines | **~+77 / −14** (additive post-OTP fields + `auth` login branch) |
| **New function** | `postOtpAccountFieldsFromSearch` |
| **Modified functions** | `verifyUserRegistrationOtp`, `completeMobileOtpLogin` |
| **Unchanged contract** | `lookupMobileRegistration` (still `{ ok, conflict }` only) |

**Worktree tests (OTP-focused):** `node --test test/login_role_lookup_scenarios.test.js test/otp_send_verify_roundtrip.test.js` → **7 pass / 0 fail** (after `npm ci` in worktree).

---

## Env key names (hotfix code vs today local template)

Method: `docs/audit/STALE_REDEPLOY_ENV_DIFF.md` (names only, no values).

| Set | Count (this machine) |
|-----|---------------------:|
| Keys in `backend/functions/.env` today | **38** |
| Keys in `9883f00` `.env.example` | **58** (template at Oct 24 tip; includes names not all present locally) |

**Hotfix `registration_otp.js` at `9883f00` still reads** (non-exhaustive): `MSG91_*`, `REVIEW_*`, `APP_ENV`, `ENABLE_REVIEW_DEMO`, Redis/`OTP_*`, Supabase service role via existing helpers, demo phone envs, `ALLOW_LEGACY_UNSALTED_OTP_HASH`, etc.

**Today `.env` adds names** (vs Oct 6 cohort proxy in STALE doc): e.g. `MSG91_AUTH_KEY`, `OTP_REDIS_MIRROR`, `SUPABASE_ANON_KEY`, `SUPABASE_PUBLISHABLE_KEY`, … — ensure Cloud Run has **canonical names** before hotfix deploy (no values in this doc).

**Do not** run scripts that consume `STAGING_SUPABASE_*` or production service account JSON for this prep.

---

## Deploy order

1. **Frontend + backend together** in one release window (preferred): backend patch from `..\doctor-hotfix`, then app build from `chore/dedupe-structure-audit`.
2. If backend must lead by minutes: canary **`verifyUserRegistrationOtp`**, then **`completeMobileOtpLogin`**, then ship frontend — old app remains safe on legacy fallback until step 2 completes.

---

## Commands from `..\doctor-hotfix` (operator — placeholders)

Preflight (no deploy yet):

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor-hotfix
git status   # expect detached HEAD 9883f00 + modified registration_otp.js only
cd backend\functions
npm ci
node --test test\login_role_lookup_scenarios.test.js test\otp_send_verify_roundtrip.test.js
node scripts/predeploy_secret_check.js   # if used in your runbook
```

**Canary — `verifyUserRegistrationOtp` only** (replace project/region):

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor-hotfix
firebase deploy --only functions:verifyUserRegistrationOtp --project <FIREBASE_PROJECT_ID>
# Optional: route small % traffic to new revision via Cloud Run console / gcloud run services update-traffic
```

**Validate canary logs** (Cloud Logging):

- Successful registration OTP: log line `Registration OTP verified successfully` and response includes **`exists`** / **`role`** (client logs or callable test).
- Wrong OTP: **`permission-denied`** / invalid OTP — **no** success payload with `exists`/`role`.
- Login OTP: `Login OTP verified successfully, customToken minted` with **`exists: true`** and **`role`**.

**Second callable — `completeMobileOtpLogin`:**

```powershell
firebase deploy --only functions:completeMobileOtpLogin --project <FIREBASE_PROJECT_ID>
```

**Do not** from chore branch:

```text
firebase deploy --only functions
```

Full deploy from `chore/dedupe-structure-audit` **drops 22 Firestore trigger exports** vs Oct-era fleet — see `DEPLOY_HASH_COHORT.md`.

---

## Rollback (traffic, not git)

1. Cloud Run → service for each function → **Revisions** → move **100% traffic** to previous revision (`<PREVIOUS_REVISION_ID>`).
2. Or `gcloud run services update-traffic <SERVICE_NAME> --to-revisions=<PREVIOUS_REVISION_ID>=100 --region=<REGION> --project=<PROJECT>`.
3. Confirm client still works with **old** frontend (no `exists`/`role` required — additive fields ignored by old apps).

---

## Post-deploy checks

- `lookupMobileRegistration` still returns only `{ ok, conflict }` (privacy).
- Generic mobile login: after OTP, app receives role without role picker (new frontend).
- Wrong role card: blocked message, not registration.
- Rate limits unchanged: verify uses **`enforceAbuseLimit(..., 'api')`**; complete login uses **`enforceAbuseLimit(..., 'login')`**; App Check enforced on callables via `enforceAppCheck: ENFORCE_OTP_APP_CHECK` / OTP options.

---

## References

- Main repo tests: `backend/functions/test/login_role_lookup_scenarios.test.js`, `test/otp_send_verify_roundtrip.test.js`
- Baselines: `docs/audit/baseline_backend_default_npm_test.txt`, `baseline_flutter_failing_tests.txt`
