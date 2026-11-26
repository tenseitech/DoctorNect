-- Anon discovery: SECURITY DEFINER read of verified doctors (no anon EXECUTE on current_profile_id; no direct doctors SELECT).

DROP FUNCTION IF EXISTS public.doctor_directory_rows();

CREATE FUNCTION public.doctor_directory_rows()
RETURNS TABLE (
    doctor_id character varying(64),
    name character varying(255),
    specialization character varying(128),
    super_specialization text,
    qualification character varying(255),
    experience_years integer,
    consultation_fee numeric(10, 2),
    clinic_name character varying(255),
    area character varying(128),
    city character varying(128),
    state character varying(128),
    country character varying(64),
    pincode character varying(16),
    address_line1 text,
    address_line2 text,
    about text,
    languages text[],
    photo_url text,
    photo_s3_key text,
    rating numeric(3, 2),
    review_count integer,
    verified boolean,
    profile_completed boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT
        d.doctor_id,
        d.name,
        d.specialization,
        d.super_specialization,
        d.qualification,
        d.experience_years,
        d.consultation_fee,
        d.clinic_name,
        d.area,
        d.city,
        d.state,
        d.country,
        d.pincode,
        d.address_line1,
        d.address_line2,
        d.about,
        d.languages,
        d.photo_url,
        d.photo_s3_key,
        d.rating,
        d.review_count,
        d.verified,
        d.profile_completed
    FROM public.doctors AS d
    WHERE d.verified IS TRUE AND d.deactivated IS FALSE;
$$;

REVOKE ALL ON FUNCTION public.doctor_directory_rows() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.doctor_directory_rows() TO anon, authenticated, service_role;

DO $$
DECLARE
    v_owner name := current_user;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doctornect_admin') THEN
        v_owner := 'doctornect_admin';
    ELSIF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_master') THEN
        v_owner := 'rds_master';
    END IF;
    EXECUTE format('ALTER FUNCTION public.doctor_directory_rows() OWNER TO %I', v_owner);
END
$$;

DROP POLICY IF EXISTS "review_public_anon_select" ON public.review_public;

DROP VIEW IF EXISTS public.doctor_directory;

CREATE VIEW public.doctor_directory
WITH (security_invoker = false)
AS
SELECT
    doctor_id,
    name,
    specialization,
    super_specialization,
    qualification,
    experience_years,
    consultation_fee,
    clinic_name,
    area,
    city,
    state,
    country,
    pincode,
    address_line1,
    address_line2,
    about,
    languages,
    photo_url,
    photo_s3_key,
    rating,
    review_count,
    verified,
    profile_completed
FROM public.doctor_directory_rows();

CREATE POLICY "review_public_anon_select"
    ON public.review_public
    FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1
            FROM public.doctor_directory AS dd
            WHERE dd.doctor_id = review_public.doctor_id
        )
    );

DO $$
DECLARE
    v_owner name := current_user;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doctornect_admin') THEN
        v_owner := 'doctornect_admin';
    ELSIF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_master') THEN
        v_owner := 'rds_master';
    END IF;
    EXECUTE format('ALTER VIEW public.doctor_directory OWNER TO %I', v_owner);
END
$$;

REVOKE ALL ON public.doctor_directory FROM PUBLIC;
GRANT SELECT ON public.doctor_directory TO anon, authenticated, service_role;

REVOKE ALL ON TABLE public.doctors FROM anon;

DROP POLICY IF EXISTS doctors_select_directory_definer ON public.doctors;

DO $policy$
DECLARE
    roles text[] := ARRAY[]::text[];
    role_list text;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doctornect_admin') THEN
        roles := array_append(roles, 'doctornect_admin');
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_master') THEN
        roles := array_append(roles, 'rds_master');
    END IF;
    IF array_length(roles, 1) IS NULL THEN
        RAISE NOTICE 'doctors_select_directory_definer: no target roles; policy not created';
        RETURN;
    END IF;
    SELECT string_agg(quote_ident(r), ', ') INTO role_list FROM unnest(roles) AS t(r);
    EXECUTE format(
        'CREATE POLICY doctors_select_directory_definer ON public.doctors FOR SELECT TO %s USING (verified IS TRUE AND deactivated IS FALSE)',
        role_list
    );
END;
$policy$;