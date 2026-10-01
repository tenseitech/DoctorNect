-- ============================================================================
-- DoctorNect Platform — Automated User Provisioning Migration
-- Migration: 20260930000005_users_provisioning.sql
-- Description: Provision a public.users row automatically upon auth.users creation.
-- Extracts role strictly from raw_app_meta_data, generates cryptographically
-- random profile_id via gen_random_uuid(), normalizes 10-digit mobile, safely
-- handles NULL emails, logs failure diagnostics to private.provisioning_errors,
-- and prevents signup breakage.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. AUDIT & DIAGNOSTIC TABLE IN private SCHEMA
-- ============================================================================
-- Captures provisioning failures without failing user authentication signups.

CREATE TABLE IF NOT EXISTS private.provisioning_errors (
    id BIGSERIAL PRIMARY KEY,
    auth_user_id UUID,
    error TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE private.provisioning_errors ENABLE ROW LEVEL SECURITY;

-- Deny all client access (no policies defined)
REVOKE ALL ON TABLE private.provisioning_errors FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE private.provisioning_errors TO postgres, service_role;

-- ============================================================================
-- 2. USER PROVISIONING TRIGGER FUNCTION IN private SCHEMA
-- ============================================================================

CREATE OR REPLACE FUNCTION private.on_auth_user_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_raw_role TEXT;
    v_role TEXT;
    v_prefix TEXT;
    v_random_suffix TEXT;
    v_profile_id TEXT;
    v_email TEXT;
    v_raw_mobile TEXT;
    v_mobile TEXT;
    v_display_name TEXT;
    v_status TEXT;
BEGIN
    -- 0. Check for skip_provision flag in raw_app_meta_data (Admin SDK / migration scripts bypass)
    IF NEW.raw_app_meta_data ->> 'skip_provision' = 'true' THEN
        RETURN NEW;
    END IF;

    -- 1. Role extraction strictly from raw_app_meta_data (Never trust raw_user_meta_data)
    v_raw_role := NEW.raw_app_meta_data ->> 'role';

    -- Whitelist allowed roles; default safely to 'patient' (Never permit admin roles here)
    IF v_raw_role IN ('patient', 'doctor', 'medicalStore', 'lab', 'ambulance') THEN
        v_role := v_raw_role;
    ELSE
        v_role := 'patient';
    END IF;

    -- 2. Determine deterministic role prefix
    v_prefix := CASE v_role
        WHEN 'doctor' THEN 'd_'
        WHEN 'patient' THEN 'p_'
        WHEN 'medicalStore' THEN 'm_'
        WHEN 'lab' THEN 'l_'
        WHEN 'ambulance' THEN 'a_'
        ELSE 'p_'
    END;

    -- 3. Generate cryptographically strong, non-guessable profile_id (Total <= 64 chars)
    -- Uses gen_random_uuid() (standard pg_catalog function, valid on search_path = public, pg_temp)
    -- Prefix (2 chars) + 32-char hex random token = 34 chars
    v_random_suffix := replace(gen_random_uuid()::text, '-', '');
    v_profile_id := v_prefix || v_random_suffix;

    -- 4. Safe email fallback (users.email is NOT NULL UNIQUE)
    IF NEW.email IS NOT NULL AND btrim(NEW.email) != '' THEN
        v_email := btrim(NEW.email);
    ELSE
        v_email := NEW.id::text || '@users.doctornect.invalid';
    END IF;

    -- 5. Extract and normalize mobile to exactly 10 digits (matching auth-otp lookups)
    -- Priority: NEW.phone (E.164 e.g. +91XXXXXXXXXX), falling back to app_metadata/user_metadata mobile
    IF NEW.phone IS NOT NULL AND btrim(NEW.phone) != '' THEN
        v_raw_mobile := NEW.phone;
    ELSE
        v_raw_mobile := COALESCE(
            NEW.raw_app_meta_data ->> 'mobile',
            NEW.raw_user_meta_data ->> 'mobile'
        );
    END IF;

    IF v_raw_mobile IS NOT NULL THEN
        v_mobile := NULLIF(right(regexp_replace(v_raw_mobile, '\D', '', 'g'), 10), '');
    ELSE
        v_mobile := NULL;
    END IF;

    -- 6. Extract display_name metadata
    v_display_name := COALESCE(
        NEW.raw_user_meta_data ->> 'display_name',
        NEW.raw_user_meta_data ->> 'name',
        ''
    );

    -- 7. Initial status per platform convention
    v_status := CASE 
        WHEN v_role = 'patient' THEN 'approved'
        ELSE 'pending_review'
    END;

    -- 8. Insert into public.users; protect against aborting auth signup on any unexpected error
    BEGIN
        INSERT INTO public.users (
            id,
            role,
            profile_id,
            display_name,
            email,
            mobile,
            profile_completed,
            verified,
            deactivated,
            status
        ) VALUES (
            NEW.id,
            v_role,
            v_profile_id,
            v_display_name,
            v_email,
            v_mobile,
            FALSE,
            FALSE,
            FALSE,
            v_status
        )
        ON CONFLICT (id) DO NOTHING;
    EXCEPTION 
        WHEN unique_violation THEN
            -- Email unique collision (e.g. reused email or synthetic pattern)
            -- Log warning and retry with non-colliding fallback email
            BEGIN
                INSERT INTO private.provisioning_errors (auth_user_id, error)
                VALUES (NEW.id, 'unique_violation on email (' || v_email || '), retrying with synthetic fallback: ' || SQLERRM);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;

            v_email := NEW.id::text || '@users.doctornect.invalid';
            BEGIN
                INSERT INTO public.users (
                    id, role, profile_id, display_name, email, mobile,
                    profile_completed, verified, deactivated, status
                ) VALUES (
                    NEW.id, v_role, v_profile_id, v_display_name, v_email, v_mobile,
                    FALSE, FALSE, FALSE, v_status
                )
                ON CONFLICT (id) DO NOTHING;
            EXCEPTION WHEN OTHERS THEN
                BEGIN
                    INSERT INTO private.provisioning_errors (auth_user_id, error)
                    VALUES (NEW.id, 'Retry with fallback email failed: ' || SQLERRM);
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
                RAISE WARNING 'private.on_auth_user_created: Retry failed for auth.users id %: %', NEW.id, SQLERRM;
            END;
        WHEN OTHERS THEN
            -- Log diagnostic error safely inside isolated block
            BEGIN
                INSERT INTO private.provisioning_errors (auth_user_id, error)
                VALUES (NEW.id, SQLERRM);
            EXCEPTION WHEN OTHERS THEN
                NULL; -- Error logging must never abort transaction
            END;

            RAISE WARNING 'private.on_auth_user_created: Failed to insert public.users for auth.users id %: %',
                NEW.id, SQLERRM;
    END;

    RETURN NEW;
END;
$$;

-- Revoke execute from public/anon/authenticated roles
REVOKE ALL ON FUNCTION private.on_auth_user_created() FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 3. BIND TRIGGER TO auth.users
-- ============================================================================

DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION private.on_auth_user_created();

COMMIT;
