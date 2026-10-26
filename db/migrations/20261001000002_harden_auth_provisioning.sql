-- ============================================================================
-- DoctorNect Platform — Hardened Auth Provisioning, OTP & Rate Limiting
-- Migration: 20261001000002_harden_auth_provisioning.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. PATIENTS DEFAULT owner_uid
-- ============================================================================
-- Ensures client upserts without owner_uid default to auth.uid(), while
-- allowing explicit owner_uid overrides for migration and service_role scripts.
ALTER TABLE public.patients ALTER COLUMN owner_uid SET DEFAULT auth.uid();


-- ============================================================================
-- 2. HARDENED USER PROVISIONING TRIGGER (PRE-REGISTRATION HIJACK PREVENTION)
-- ============================================================================
-- Prevents pre-registration account hijack:
-- 1. If raw_app_meta_data->>'role' IS NULL, RETURN NEW immediately without provisioning.
-- 2. Mobile extracted strictly from NEW.phone (when phone_confirmed_at IS NOT NULL)
--    or raw_app_meta_data->>'mobile'. NEVER trusts raw_user_meta_data.

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

    -- Pre-registration hijack defense: public self-signups without service_role role get no profile
    IF v_raw_role IS NULL THEN
        RETURN NEW;
    END IF;

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
    v_random_suffix := replace(gen_random_uuid()::text, '-', '');
    v_profile_id := v_prefix || v_random_suffix;

    -- 4. Safe email fallback (users.email is NOT NULL UNIQUE)
    IF NEW.email IS NOT NULL AND btrim(NEW.email) != '' THEN
        v_email := btrim(NEW.email);
    ELSE
        v_email := NEW.id::text || '@signup.doctornect.app';
    END IF;

    -- 5. Extract and normalize mobile to exactly 10 digits
    -- Mobile only from NEW.phone when phone_confirmed_at IS NOT NULL, or raw_app_meta_data->>'mobile'
    -- NEVER raw_user_meta_data
    IF NEW.phone IS NOT NULL AND btrim(NEW.phone) != '' AND NEW.phone_confirmed_at IS NOT NULL THEN
        v_raw_mobile := NEW.phone;
    ELSE
        v_raw_mobile := NEW.raw_app_meta_data ->> 'mobile';
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
            BEGIN
                INSERT INTO private.provisioning_errors (auth_user_id, error)
                VALUES (NEW.id, 'unique_violation on email (' || v_email || '), retrying with synthetic fallback: ' || SQLERRM);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;

            v_email := NEW.id::text || '@signup.doctornect.app';
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
            BEGIN
                INSERT INTO private.provisioning_errors (auth_user_id, error)
                VALUES (NEW.id, SQLERRM);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;

            RAISE WARNING 'private.on_auth_user_created: Failed to insert public.users for auth.users id %: %',
                NEW.id, SQLERRM;
    END;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.on_auth_user_created() FROM PUBLIC, anon, authenticated;


-- ============================================================================
-- 3. PHONE-ONLY AUTH USER LOOKUP
-- ============================================================================
DROP FUNCTION IF EXISTS public.find_auth_user(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.find_auth_user(TEXT);

CREATE OR REPLACE FUNCTION public.find_auth_user(
    p_phone TEXT
)
RETURNS TABLE (
    id UUID,
    email TEXT,
    phone TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, pg_temp
AS $$
    SELECT
        u.id,
        u.email::TEXT,
        u.phone::TEXT
    FROM auth.users u
    WHERE
        p_phone IS NOT NULL
        AND p_phone <> ''
        AND right(regexp_replace(COALESCE(u.phone, ''), '\D', '', 'g'), 10)
            = right(regexp_replace(p_phone, '\D', '', 'g'), 10)
        AND length(right(regexp_replace(COALESCE(u.phone, ''), '\D', '', 'g'), 10)) = 10
    ORDER BY u.created_at
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.find_auth_user(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_auth_user(TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_auth_user(TEXT) TO service_role;


-- ============================================================================
-- 4. ATOMIC OTP ATTEMPTS CONSUMPTION
-- ============================================================================
CREATE OR REPLACE FUNCTION public.consume_otp_attempt(p_challenge_id TEXT)
RETURNS TABLE(attempts INT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    UPDATE public.otp_challenges
    SET attempts = attempts + 1
    WHERE challenge_id = p_challenge_id
      AND attempts < 5
    RETURNING attempts;
$$;

REVOKE ALL ON FUNCTION public.consume_otp_attempt(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.consume_otp_attempt(TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_otp_attempt(TEXT) TO service_role;


-- ============================================================================
-- 5. ATOMIC RATE LIMIT INCREMENT / WINDOW UPSERT
-- ============================================================================
CREATE OR REPLACE FUNCTION public.check_and_increment_rate_limit(
    p_bucket TEXT,
    p_max_count INT,
    p_window_seconds INT,
    p_category TEXT DEFAULT 'otp'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_allowed BOOLEAN;
BEGIN
    INSERT INTO public.abuse_rate_limits (bucket, count, category, window_start, updated_at)
    VALUES (p_bucket, 1, p_category, NOW(), NOW())
    ON CONFLICT (bucket) DO UPDATE SET
        count = CASE
            WHEN NOW() - abuse_rate_limits.window_start >= (p_window_seconds || ' seconds')::INTERVAL THEN 1
            ELSE abuse_rate_limits.count + 1
        END,
        window_start = CASE
            WHEN NOW() - abuse_rate_limits.window_start >= (p_window_seconds || ' seconds')::INTERVAL THEN NOW()
            ELSE abuse_rate_limits.window_start
        END,
        updated_at = NOW()
    RETURNING (abuse_rate_limits.count <= p_max_count) INTO v_allowed;

    RETURN COALESCE(v_allowed, TRUE);
END;
$$;

REVOKE ALL ON FUNCTION public.check_and_increment_rate_limit(TEXT, INT, INT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_and_increment_rate_limit(TEXT, INT, INT, TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_increment_rate_limit(TEXT, INT, INT, TEXT) TO service_role;


-- ============================================================================
-- 6. SERVICE_ROLE-ONLY LOCK ON otp_challenges & abuse_rate_limits
-- ============================================================================
DROP POLICY IF EXISTS "otp_challenges_deny_all" ON public.otp_challenges;
DROP POLICY IF EXISTS "abuse_rate_limits_deny_all" ON public.abuse_rate_limits;

ALTER TABLE public.otp_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.abuse_rate_limits ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.otp_challenges FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.abuse_rate_limits FROM PUBLIC, anon, authenticated;

GRANT ALL ON TABLE public.otp_challenges TO postgres, service_role;
GRANT ALL ON TABLE public.abuse_rate_limits TO postgres, service_role;

COMMIT;
