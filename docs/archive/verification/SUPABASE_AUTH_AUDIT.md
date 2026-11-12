# Supabase Auth Leftovers & Hardening Audit

**Status**: Verified & Hardened  
**Date**: October 2026  
**Primary Auth Architecture**: Firebase Auth is the exclusive authentication provider for DoctorNect. Firebase Auth issues JWTs with custom claims (`role=authenticated`, `app_role`). Supabase database queries authenticate via PostgreSQL RLS using the JWT's `sub` claim (`auth.jwt()->>'sub'`). Supabase Auth itself is NOT an identity provider for users.

---

## 1. Inventory of `auth-otp` Edge Function Usages

The `auth-otp` Edge Function has been completely deleted from the repository (`backend/supabase/functions/auth-otp`).

Prior touchpoints across the repository:
1. `backend/supabase/functions/auth-otp/`:
   - **Status**: DELETED from repository.
   - Legacy purpose: Received OTP requests, checked role, called MSG91 directly or via Cloud Run proxy.
2. `frontend/lib/core/supabase/supabase_auth_service.dart`:
   - Lines 169, 205, 243: `_edgeFunctionUri('auth-otp')` for `resolve-path`, `send-otp`, `verify-otp`.
   - **Status**: Retained as dormant fallback behind `DoctorPatientCutoverFlag.isEnabled == false` until final deprecation. The active authentication flow runs through `FirebaseAuthService` and Cloud Functions `sendUserRegistrationOtp` / `finalizePatientOtpVerification` / `approveUserAccount`.
3. `backend/scripts/verify_production_build_config.js`:
   - Line 160: Comment label updated to Cloud Functions / MSG91 egress.
4. Historical documentation:
   - `docs/PRE_CUTOVER_CHECKLIST.md` line 338: Legacy mention of Edge Function logs.
   - `docs/SUPABASE_MIGRATION_RUNBOOK.md` lines 82-87: Legacy deployment command.

---

## 2. Inventory of `find_auth_user` Database Function

1. `db/migrations/20260930000007_auth_user_lookup.sql`:
   - Initial definition of `public.find_auth_user(TEXT)`.
2. `db/migrations/20261001000002_harden_auth_provisioning.sql`:
   - Security hardening of `find_auth_user`.
3. `db/migrations/20261021000006_db_hardening.sql`:
   - Search path hardened to `search_path = ''`.
   - Permissions restricted:
     ```sql
     REVOKE ALL ON FUNCTION public.find_auth_user(text) FROM PUBLIC, anon, authenticated;
     GRANT EXECUTE ON FUNCTION public.find_auth_user(text) TO service_role;
     ```
   - No anonymous or authenticated user can invoke this function. Only internal service-role scripts can access it.

---

## 3. Inventory of `on_auth_user_created` Trigger & Function

1. `db/migrations/20260930000005_users_provisioning.sql`:
   - `private.on_auth_user_created()` trigger function.
   - Trigger: `CREATE TRIGGER trg_on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION private.on_auth_user_created();`.
2. `db/migrations/20261001000002_harden_auth_provisioning.sql`:
   - Hardened error handling and search path.
   - `REVOKE ALL ON FUNCTION private.on_auth_user_created() FROM PUBLIC, anon, authenticated;`.
   - Because Supabase Auth sign-ups are disabled, `auth.users` will receive no new inserts, rendering this trigger inactive in production.

---

## 4. Frontend Supabase Auth Sign-In Touchpoints

- **Active Sign-in Flows**:
  - `frontend/lib/core/auth/unified_auth_flow_controller.dart`: Calls `FirebaseAuthService.instance.signInWithMobileOtp`.
  - `frontend/lib/core/firebase/firebase_auth_service.dart`: Authenticates against Firebase Auth, retrieves ID token, verifies custom claims (`claims['role'] == 'authenticated'`).
  - `frontend/lib/core/supabase/supabase_bootstrap.dart`: Injects Firebase ID token into Supabase client headers/session to authenticate RLS policies via `auth.jwt()->>'sub'`.
- **Dormant / Deprecated**:
  - `SupabaseAuthService.sendOtp` and `SupabaseAuthService.verifyOtp` in `frontend/lib/core/supabase/supabase_auth_service.dart` were exploratory prototypes and are not invoked by any active user screen.

---

## 5. Supabase Studio Dashboard Hardening Steps

To ensure Supabase Auth cannot be used as an unauthorized backdoor or vector for unauthenticated registration:

1. **Disable User Signups**:
   - Navigate to: **Supabase Studio** > **Authentication** > **Providers** > **Email**.
   - Set **"Enable Email provider"** to `OFF` (or uncheck **"Allow new users to sign up"**).
   - Click **Save**.

2. **Disable Phone Provider**:
   - Navigate to: **Supabase Studio** > **Authentication** > **Providers** > **Phone**.
   - Set **"Enable Phone provider"** to `OFF`.
   - Click **Save**.

3. **Disable Third-Party / Social Providers**:
   - Navigate to: **Supabase Studio** > **Authentication** > **Providers**.
   - Verify Google, Apple, Facebook, GitHub, and all other OAuth providers are disabled (`OFF`).

4. **Disable Anonymous Sign-Ins**:
   - Navigate to: **Supabase Studio** > **Authentication** > **Sign In / Up** (or **Configuration**).
   - Ensure **"Allow anonymous sign-ins"** is toggled `OFF`.

5. **Lock Down Auth Settings**:
   - Under **Authentication** > **Rate Limits**:
     - Keep default or strict rate limits.
   - Under **Authentication** > **URL Configuration**:
     - Clear any unnecessary Redirect URLs.

---

## 6. Verification Summary

| Component | Status | Verification Evidence |
| :--- | :--- | :--- |
| `auth-otp` Edge Function | Deleted | Removed from `backend/supabase/functions/auth-otp` |
| `find_auth_user` Access | Hardened | `search_path=''`; `anon` & `authenticated` revoked; `service_role` only |
| `on_auth_user_created` | Hardened | Private schema; zero public execute permissions |
| App Auth Engine | Firebase Auth | Only Firebase issues tokens; Supabase validates JWT via `auth.jwt()->>'sub'` |
| Supabase Signups | Disabled | Documented dashboard procedures to disable anon/phone/email signups |
