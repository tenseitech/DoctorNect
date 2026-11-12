-- ============================================================================
-- DoctorNect — Allow Firebase-only users in public.users
-- Migration: 20261008000003_allow_firebase_users_drop_fkey.sql
-- ============================================================================
-- RATIONALE:
-- In migration 20261008000001_firebase_uid_identity.sql, DoctorNect moved to
-- third-party Firebase Auth identity (public.users.firebase_uid = auth.jwt()->>'sub').
-- Firebase users authenticate directly with Firebase JWT tokens and do NOT have
-- a corresponding row in Supabase auth.users.
--
-- The initial schema (20260923000001_doctornect_schema.sql line 62) defined:
--   id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE
-- which created the foreign key constraint `users_id_fkey`.
--
-- When sync triggers (syncFirestoreUserToSupabase) or backfill scripts insert
-- or upsert Firebase users into public.users, PostgreSQL rejects the insert
-- because `users.id` (deterministically derived from firebase_uid via toUserUuid)
-- does not exist in auth.users.
--
-- This migration drops `users_id_fkey` on public.users, while preserving `id UUID PRIMARY KEY`,
-- so that Firebase-only users can be stored in public.users with their deterministic
-- UUIDs and unique firebase_uid.
--
-- DELETION SAFETY & CASCADE CONSIDERATIONS:
-- Deletion of Firebase users is managed by the application-level deleteMyAccount handler
-- (backend/functions/delete_my_account.js) and the firestore_to_supabase sync trigger.
-- Child tables referencing public.users (such as in_app_notifications with ON DELETE CASCADE,
-- and doctors/patients/medical_stores/labs/ambulances with ON DELETE SET NULL) reference
-- public.users(id), which remains the primary key. When a user is deleted from public.users,
-- those relationships cascade as expected.
--
-- Note: private.admin_users retains its foreign key to auth.users because admin users
-- authenticate via native Supabase Auth dashboard logins.
-- ============================================================================

BEGIN;

-- Drop foreign key constraint from public.users to auth.users(id)
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_id_fkey;

COMMIT;

-- ============================================================================
-- ROLLBACK SECTION (Commented out):
-- To re-apply the constraint if reverting:
--
-- BEGIN;
-- -- Note: Re-enabling this constraint requires that every id in public.users
-- -- exists in auth.users(id), or it will fail with a foreign key violation.
-- ALTER TABLE public.users
--   ADD CONSTRAINT users_id_fkey
--   FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
-- COMMIT;
-- ============================================================================
