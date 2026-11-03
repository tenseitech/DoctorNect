# App ↔ backend contract (read-only snapshot)

**Branch:** `chore/dedupe-structure-audit` (frontend).  
**Deployed baseline:** `docs/ops/baseline_cloud_functions.json` (Oct-era export list — **does not include** branch-only symbols).  
**Cohort map:** `docs/audit/DEPLOY_HASH_COHORT.md` — proxy **`9883f00` ≈ Oct 24**, **`4dfae67` ≈ Oct 31 postgres-only**, proxy **`4fc3a6b` ≈ Oct 6 / `fb8e2e13` fleet**.

**Region:** Flutter uses `FirebaseFunctions.instanceFor(region: 'asia-south1')` unless noted.

---

## 1. Callables / HTTP the frontend invokes

| Client symbol | In `baseline_cloud_functions.json`? | Expected deployed cohort | Response fields client reads | Cohort gap |
|---------------|--------------------------------------|---------------------------|------------------------------|------------|
| `sendUserRegistrationOtp` | yes | Oct 24+ | `ok`, `sessionId`, … | — |
| `verifyUserRegistrationOtp` | yes | Oct 24+ | `ok`, `sessionId`, `customToken`; **branch also reads** `exists`, `role` (post-OTP) | **Deployed Oct 24 tip lacks `exists`/`role`** unless hotfix patch; client has legacy `check()` fallback |
| `completeMobileOtpLogin` | yes | Oct 24+ | `ok`, `customToken`, `exists`, `role` | **`exists`/`role` same hotfix gap** |
| `lookupMobileRegistration` | yes | Oct 24+ | `ok`, `conflict` only | — |
| `finalizePatientOtpVerification` | yes | Oct 24+ | `ok`, `mobileVerified`, `profileId` | — |
| **`cleanupPendingRegistration`** | **no** | **branch only** | `ok`, `cleaned` | **Not deployed until canary** |
| `resetUserPasswordWithOtp` | yes | Oct 24+ | success flags | — |
| `assertAccountCreationAllowed` | yes | Oct 24+ | errors only | — |
| `assertLoginAllowed` / `recordFailedLogin` / `clearFailedLogins` | yes | Oct 24+ | — | — |
| `consumeAiGenerationQuota` | yes | Oct 24+ | quota fields | — |
| `deleteMyAccount` | yes | Oct 24+ | — | — |
| `bookAppointment` / `rescheduleAppointment` | yes | Oct 24+ | appointment payload | — |
| `getValidationRules` / `validateField` / `validateFormFields` / `validateVitalAdvisory` | yes | Oct 24+ | rules / errors | — |
| `getS3UploadUrl` / `getS3DownloadUrl` / `getS3DownloadUrls` / `deleteS3Object` / `confirmS3Upload` | yes | Oct 24+ | URLs / audit | — |
| `createRazorpayOrder` / `verifyRazorpayPayment` | yes | Oct 24+ | order / payment | — |
| `reviewPromotedAd` | yes | Oct 24+ | — | — |
| `getAmbulanceInvite` | yes | Oct 24+ | invite payload | — |
| `resetAmbulanceDriverPin` | yes | Oct 24+ | — | — |
| `submitAmbulanceRating` | yes | Oct 24+ | — | — |
| `verifyAmbulanceDriverLogin` | yes | Oct 24+ | login payload | — |
| `verifyAmbulanceDriverLoginHttp` | yes (HTTP) | Oct 24+ | web CORS login | — |
| `resyncAmbulanceAuthUid` | yes | Oct 24+ | `ok`, `driverId` | — |
| `getValidationRulesHttp` | yes (HTTP) | Oct 24+ | not used by Flutter app directly | — |

---

## 2. Firestore collections still touched by the client

With **`FIRESTORE_FORBIDDEN` / postgres-primary** on the client, many paths use Supabase; **Firestore remains** in:

| Area | Collections / paths (examples) | If Firestore forbidden client-side but backend still writes Firestore |
|------|--------------------------------|----------------------------------------------------------------------|
| Ambulance driver / ops | `ambulances`, `users`, batches in `ambulance_repository.dart`, profile screen | Driver location / request UI may **miss realtime** updates; callables still sync to Supabase on backend |
| Promoted ads | `promoted_ads` via `promoted_ads_service.dart` | Ad listing / payment UI breaks unless migrated to Supabase reads |
| Super admin verification | `super_admin_verification_service.dart` | Admin verification queue breaks |
| Lab orders / connections (legacy repos) | lab connection/order repositories | Mixed — many modules use Supabase on branch |
| Doctor shell / notifications | direct `FirebaseFirestore.instance` watches | Stale or empty streams if rules deny client |

**Branch intent:** doctor/patient/pharmacy/lab/ambulance **primary reads** move to Supabase; Firestore is **legacy / ambulance / ads / admin** pockets.

---

## 3. Supabase tables / RPC (client direct) — RLS policy names (consolidated migration)

Policies from `db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql` (names only). Role = app role using JWT `sub` / helpers.

| Table | Patient | Doctor | Lab / pharmacy / ambulance | Admin |
|-------|---------|--------|---------------------------|-------|
| `users` | `users_select_owner_or_admin`, `users_insert_self_or_admin`, `users_update_owner_or_admin` | same | same | `users_*_admin` via `private.is_super_admin()` |
| `patients` | `patients_select`, `patients_insert`, `patients_update` (owner) | `patients_select` via `private.doctor_can_access_patient` | — | `patients_delete_admin` |
| `doctors` | `doctors_select` (verified directory) | `doctors_select`, `doctors_insert`, `doctors_update` (owner) | — | `doctors_delete_admin` |
| `appointments` | `appointments_select`, `appointments_insert`, … | same | — | `appointments_delete_admin` |
| `prescriptions` | policies in same migration module | doctor/patient split | — | admin variants |
| `labs` / `medical_stores` / `ambulances` | read via directory / owner policies in later migrations (`labs_update`, `ambulances_update`, …) | — | owner update policies | admin |

**Client DELETE on `users` / `patients` / `doctors`:** no owner DELETE policy — **`users_delete_admin`**, **`patients_delete_admin`**, **`doctors_delete_admin`** only. Orphan cleanup must use **`cleanupPendingRegistration`** (service role).

No broad client RPC list documented here; client uses PostgREST `.from(...)` primarily.

---

## 4. Gap table (release blockers)

| Gap | Frontend needs | Deployed / backend @ Oct 24 baseline | Mitigation |
|-----|----------------|--------------------------------------|------------|
| G1 | Post-OTP `exists` / `role` on verify/login | Missing on `9883f00` | Hotfix patch on `registration_otp.js` or wait for legacy fallback |
| G2 | `cleanupPendingRegistration` callable | **Not in baseline export list** | Deploy `--only functions:cleanupPendingRegistration` before app |
| G3 | RLS-safe orphan row delete | Client `.delete()` blocked | Callable (G2) |
| G4 | Full postgres-only client | Some Firestore reads remain | Module cutover / `FIRESTORE_FORBIDDEN` testing |
| G5 | Oct 31 (`4dfae67`) full functions tree | 22 triggers dropped vs Oct 24 | **Do not** full deploy from chore branch without cutover plan |

---

## 5. Related docs

- `docs/audit/CLEANUP_CALLABLE_DEPLOY_PLAN.md`
- `docs/audit/LOGIN_HOTFIX_DEPLOY_PLAN.md`
- `docs/audit/DEPLOY_HASH_COHORT.md`
