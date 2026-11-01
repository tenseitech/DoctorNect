# Deploy tiers, build commits, and SUPABASE_URL hash cohorts

**Sources:** `docs/ops/STALE_REF_REDEPLOY_PLAN.md`, `docs/ops/PROGRESS.md`, `docs/archive/verification/SECURITY_AUDIT_2026-10-06.md`, `docs/audit/PROD_WIRING_CHECK.md`.  
**No hostnames or secret values.**

---

## `fb8e2e13` vs Oct 24 / Oct 31 deploy commits (`git diff --stat`, names and counts only)

**`fb8e2e13`** is a **Cloud Run revision / build id** from **SECURITY_AUDIT_2026-10-06** (not a git object in this clone).  
**Git proxy for that fleet era:** **`4fc3a6b`** — last commit before **2026-10-06 05:30 UTC** (same window as the audited deploy timestamps).

| Compare | Oct 24 build commit | Oct 31 build commit |
|---------|---------------------|---------------------|
| Tip commit (functions-relevant) | **`9883f00`** — `fix(functions): sync package-lock with supabase-js dependency` | **`4dfae67`** — `backend: Postgres-only functions, outbox worker, tests` |
| Same-day notes | Audit / Secret Manager / STALE_REF plan commits **2026-10-23..24** (`641f532`, `6cd5d00`, `d6a34c8`, …) — docs + binding fixes, not a separate “50-function tier” execution | Later same day: **`5c107e9`** (dedupe safety snapshot), **`92a983c`** (env parity / `S3_BUCKET`) — chore, not the functions architecture slice |

### `4fc3a6b` → **`9883f00`** (proxy **`fb8e2e13`** → **24 Oct**)

| Scope | Files changed | Insertions | Deletions |
|-------|---------------|------------|-----------|
| `backend/functions/` | **76** | **23,313** | **2,108** |
| Whole repo | **466** | **77,488** | **272,253** |

Notable **non-test** paths under `backend/functions/`: `index.js`, `registration_otp.js`, `delete_my_account.js`, `s3_storage.js`, `secure_config.js`, `appointment_slots.js`, `promoted_ads.js`, `cross_role_sync.js`, `mail_dispatcher.js`, …

### `4fc3a6b` → **`4dfae67`** (proxy **`fb8e2e13`** → **31 Oct** functions slice)

| Scope | Files changed | Insertions | Deletions |
|-------|---------------|------------|-----------|
| `backend/functions/` | **87** | **24,758** | **3,662** |
| Whole repo | **723** | **123,475** | **283,223** |

`backend/functions/index.js` alone: **189** insertions, **896** deletions vs proxy.

---

## **800DB356** cohort redeploy **from `fb8e2e13` / proxy `4fc3a6b`**

| Question | Answer |
|----------|--------|
| Redeploy stale cohort **at the same build** as today (`fb8e2e13`) | **No exported-function JavaScript delta** — only rebaked **`SUPABASE_URL`** / env and secret bindings change (hash **800DB356** → **40D01C23** when deploy env is corrected). |
| Redeploy same cohort **from `9883f00` (24 Oct)** instead | All **50** STALE_REF exports still exist; shared modules **`registration_otp.js`**, **`delete_my_account.js`**, **`s3_storage.js`**, **`index.js`**, etc. differ from proxy — **OTP/login/register**, **delete account**, **S3**, **validation** callables pick up Oct audit fixes. |
| Redeploy from **`4dfae67` (31 Oct postgres-only)** instead | **22** Tier-1 Firestore triggers **dropped from exports**; **28** cohort callables remain exported but sit on postgres-only / outbox architecture — **do not** use for STALE_REF env-only refresh without explicit cutover review. |

**Five `fb8e2e13` names** (`bookAppointment`, `expirePromotedAds`, `sendUserRegistrationOtp`, `verifyUserRegistrationOtp`, `reconcileAppointmentSlot`) are documented on **40D01C23** in SECURITY_AUDIT — **not** part of the STALE_REF 50.

---

## STALE_REF redeploy tiers (plan only — smallest risk first)

Execute only with operator approval. Preflight: `node scripts/predeploy_secret_check.js` per batch in `docs/ops/LAUNCH_RUNBOOK.md`.

### Tier 1 — Async Firestore triggers (18)

```bash
firebase deploy --only \
  functions:notifyDoctorOnAppointmentCreated,\
  functions:notifyDoctorOnReferralCreated,\
  functions:notifyPatientOnAppointmentStatusChanged,\
  functions:notifyPatientOnLabBookingUpdate,\
  functions:notifyPatientOnLabReportReady,\
  functions:notifyPatientOnLabOrderCreated,\
  functions:notifyDoctorOnLabConnectionChanged,\
  functions:notifyDoctorOnPharmacyConnectionChanged,\
  functions:notifyPatientOnPharmacyDeliveryCreated,\
  functions:notifyDoctorOnPharmacyDeliveryUpdated,\
  functions:notifyPatientOnPharmacyDeliveryUpdated,\
  functions:notifyAmbulanceDriverOnNewRequest,\
  functions:markAmbulanceSiblingRequestsTakenOnAccept,\
  functions:markAmbulanceSiblingRequestsOnBroadcastCancelled,\
  functions:aggregateDoctorRatingOnReviewCreate,\
  functions:aggregateDoctorRatingOnReviewWrite,\
  functions:syncReviewHelpfulCount,\
  functions:processMailQueueMsg91 \
  --project medibond-45fad
```

### Tier 2 — Validation callables (6)

```bash
firebase deploy --only \
  functions:getValidationRules,\
  functions:getValidationRulesHttp,\
  functions:validateField,\
  functions:validateFormFields,\
  functions:validateVitalAdvisory,\
  functions:consumeAiGenerationQuota \
  --project medibond-45fad
```

### Tier 3 — S3 + delete account (5)

```bash
firebase deploy --only \
  functions:getS3UploadUrl,\
  functions:getS3DownloadUrl,\
  functions:getS3DownloadUrls,\
  functions:deleteS3Object,\
  functions:deleteMyAccount \
  --project medibond-45fad
```

### Tier 4 — Razorpay (2)

```bash
firebase deploy --only \
  functions:createRazorpayOrder,\
  functions:verifyRazorpayPayment \
  --project medibond-45fad
```

### Tier 5 — Auth / OTP (11)

```bash
firebase deploy --only \
  functions:lookupMobileRegistration,\
  functions:completeMobileOtpLogin,\
  functions:finalizePatientOtpVerification,\
  functions:resetUserPasswordWithOtp,\
  functions:resetAmbulanceDriverPin,\
  functions:completeAmbulanceMobileOtpLogin,\
  functions:verifyAmbulanceDriverLogin,\
  functions:verifyAmbulanceDriverLoginHttp,\
  functions:assertLoginAllowed,\
  functions:recordFailedLogin,\
  functions:clearFailedLogins \
  --project medibond-45fad
```

### Tier 6 — Admin / ops (8)

```bash
firebase deploy --only \
  functions:approveUserAccount,\
  functions:approvePatientAccount,\
  functions:assertAccountCreationAllowed,\
  functions:backfillPatientCareTeams,\
  functions:getAmbulanceInvite,\
  functions:resyncAmbulanceAuthUid,\
  functions:sendMsg91EmailCallable,\
  functions:submitAmbulanceRating \
  --project medibond-45fad
```

**Plan doc commit:** **`d6a34c8`**. **PROGRESS.md:** no tier marked executed.

---

## Hash cohorts (verified labels)

| Hash | Cohort |
|------|--------|
| **40D01C23** | **Live-legacy** Supabase REST (docs often say “staging”) — live data store until RDS cutover; redeploys through **2026-10-31** bake this hash locally |
| **800DB356** | **2026-10-06 ~10:24Z** batch; env repoint **~11:37Z** same day without redeploy for untouched functions |

---

## Functions likely still on **800DB356**

**Rule:** Last deploy **before** env alignment redeploys after **2026-10-06 ~11:37Z**, and **not** redeployed through **2026-10-31**.

### STALE_REF **50-function registry**

`notifyDoctorOnAppointmentCreated`, `notifyDoctorOnReferralCreated`, `notifyPatientOnAppointmentStatusChanged`, `notifyPatientOnLabBookingUpdate`, `notifyPatientOnLabReportReady`, `notifyPatientOnLabOrderCreated`, `notifyDoctorOnLabConnectionChanged`, `notifyDoctorOnPharmacyConnectionChanged`, `notifyPatientOnPharmacyDeliveryCreated`, `notifyDoctorOnPharmacyDeliveryUpdated`, `notifyPatientOnPharmacyDeliveryUpdated`, `notifyAmbulanceDriverOnNewRequest`, `markAmbulanceSiblingRequestsTakenOnAccept`, `markAmbulanceSiblingRequestsOnBroadcastCancelled`, `aggregateDoctorRatingOnReviewCreate`, `aggregateDoctorRatingOnReviewWrite`, `syncReviewHelpfulCount`, `processMailQueueMsg91`, `getValidationRules`, `getValidationRulesHttp`, `validateField`, `validateFormFields`, `validateVitalAdvisory`, `consumeAiGenerationQuota`, `getS3UploadUrl`, `getS3DownloadUrl`, `getS3DownloadUrls`, `deleteS3Object`, `deleteMyAccount`, `createRazorpayOrder`, `verifyRazorpayPayment`, `lookupMobileRegistration`, `completeMobileOtpLogin`, `finalizePatientOtpVerification`, `resetUserPasswordWithOtp`, `resetAmbulanceDriverPin`, `completeAmbulanceMobileOtpLogin`, `verifyAmbulanceDriverLogin`, `verifyAmbulanceDriverLoginHttp`, `assertLoginAllowed`, `recordFailedLogin`, `clearFailedLogins`, `approveUserAccount`, `approvePatientAccount`, `assertAccountCreationAllowed`, `backfillPatientCareTeams`, `getAmbulanceInvite`, `resyncAmbulanceAuthUid`, `sendMsg91EmailCallable`, `submitAmbulanceRating`

---

## Reads **users** / **appointments**

If stuck on **800DB356**, data is **old DB snapshot** — users/appointments created after **2026-10-06** on **40D01C23** may be **invisible** to these handlers. See prior table in `docs/audit/PROD_WIRING_CHECK.md` cross-link.

**High user-impact if on 800DB356:** `lookupMobileRegistration`, OTP/login/register callables, `deleteMyAccount`, approval callables.

---

## Branch deploy warning

Redeploying stale tiers must use the **git commit / build that produced the revision currently live** for that function — **not** `chore/dedupe-structure-audit` tip alone. See `docs/audit/BRANCH_PLAN.md`.
