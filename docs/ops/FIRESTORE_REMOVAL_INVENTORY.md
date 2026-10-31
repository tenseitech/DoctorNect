# Firestore removal inventory (generated)

Generated: 2026-10-31T07:56:28.697Z
Branch: feature/postgres-only-architecture

## Scope

- **In scope:** doctor, patient, pharmacy, lab, ambulance modules + shared auth/notifications/storage.
- **Out of scope (Admin):** `frontend/lib/features/admin/`, `frontend/lib/core/admin/`

## Flutter files (0)



## Backend functions files (0)



## Flag / auth references (76 files)

- `.\.env.example`
- `.\ENVIRONMENTS.md`
- `.\docs\archive\planning\PRE_LAUNCH_CUTOVER.md`
- `.\docs\archive\planning\MIGRATION_PLAN.md`
- `.\docs\archive\planning\FIRESTORE_REMAINING.md`
- `.\docs\ARCHITECTURE_AUDIT_REPORT.md`
- `.\docs\PRE_CUTOVER_CHECKLIST.md`
- `.\docs\SUPABASE_MIGRATION_RUNBOOK.md`
- `.\docs\PLATFORM_VERIFICATION_REPORT.md`
- `.\docs\SUPABASE_AUTH_AUDIT.md`
- `.\docs\STAGING_RUNBOOK.md`
- `.\docs\SECURITY_AUDIT_2026-10-06.md`
- `.\docs\runbooks\RDS_MIGRATION_RUNBOOK.md`
- `.\backend\functions\index.js`
- `.\docs\runbooks\PRODUCTION_CUTOVER_RDS.md`
- `.\backend\functions\firestore_forbidden_guard.js`
- `.\backend\functions\delete_my_account.js`
- `.\backend\functions\abuse_rate_limit.js`
- `.\backend\functions\.env.example`
- `.\docs\reports\DOCTORNECT_FINAL_AUDIT.md`
- `.\docs\REAUDIT_REPORT.md`
- `.\docs\ops\SYNC_ROLLOUT.md`
- `.\docs\ops\STRUCTURE_PLAN.md`
- `.\backend\functions\sync_flags.js`
- `.\docs\ops\SMOKE_TEST.md`
- `.\docs\ops\REMAINING_WORK.md`
- `.\docs\ops\REDEPLOY_CHECKLIST.md`
- `.\backend\functions\security_logger.js`
- `.\docs\ops\PROGRESS.md`
- `.\backend\functions\test\user_registration_claims.test.js`
- `.\docs\ops\LAUNCH_RUNBOOK.md`
- `.\docs\ops\CLEANUP_MANIFEST.md`
- `.\backend\functions\test\supabase_webhook_idempotency.test.js`
- `.\backend\functions\test\supabase_sync_gate.test.js`
- `.\backend\functions\test\security_logger.test.js`
- `.\backend\functions\registration_otp.js`
- `.\backend\functions\test\s3_url_cache.test.js`
- `.\backend\functions\test\s3_storage.test.js`
- `.\docs\FULL_AUDIT_REPORT.md`
- `.\backend\functions\promoted_ads.js`
- `.\backend\functions\test\reviewer_login.test.js`
- `.\docs\FIXES_REPORT.md`
- `.\docs\FINAL_VERIFICATION_REPORT.md`
- `.\backend\functions\test\razorpay_webhook_security.test.js`
- `.\backend\functions\test\promoted_ads_verification.test.js`
- `.\docs\ENV_MATRIX.md`
- `.\docs\DEPLOY_CHECKLIST.md`
- `.\backend\functions\test\fcm_push.test.js`
- `.\backend\functions\test\env_parity.test.js`
- `.\backend\functions\test\otp_verification_race.test.js`
- `.\backend\functions\test\doctor_slots.test.js`
- `.\docs\db\RDS_AUTHORIZATION.md`
- `.\backend\functions\test\otp_send_verify_roundtrip.test.js`
- `.\backend\functions\test\demo_bypass_removal.test.js`
- `.\backend\functions\test\delete_my_account_supabase.test.js`
- `.\backend\functions\test\otp_send_abuse_rate_limit.test.js`
- `.\backend\functions\test\otp_retry_fallback.test.js`
- `.\backend\functions\test\otp_pure_redis_mode.test.js`
- `.\backend\functions\test\complete_ambulance_mobile_otp_login_auth_uid.test.js`
- `.\backend\functions\test\client_read_replay.rules.test.js`
- `.\backend\functions\test\caller_identity.test.js`
- `.\backend\scripts\migrate_firestore_to_supabase.js`
- `.\scripts\predeploy_secret_check.js`
- `.\scripts\ops\generate_firestore_inventory.js`
- `.\frontend\lib\main.dart`
- `.\frontend\test\release_build_supabase_guard_test.dart`
- `.\frontend\test\core\supabase\supabase_registration_gate_test.dart`
- `.\frontend\scripts\release_build.sh`
- `.\frontend\scripts\release_build.ps1`
- `.\scripts\check_env_parity.js`
- `.\frontend\.env.example`
- `.\frontend\lib\core\config\firestore_forbidden_guard.dart`
- `.\frontend\lib\core\supabase\supabase_patient_repository.dart`
- `.\frontend\lib\core\supabase\supabase_bootstrap.dart`
- `.\frontend\lib\core\supabase\supabase_auth_service.dart`
- `.\frontend\lib\core\firebase\firebase_auth_service.dart`

## Scripts marked for deletion

- `backend/scripts/migrate_firestore_to_supabase.js` — one-off migration; Postgres is canonical.

## Allowed post-cleanup exceptions

- Admin module (out of scope)
- `backend/firestore.rules` deny-all
- Historical docs mentioning Firestore
- Removed rules tests (obsolete after deny-all)
