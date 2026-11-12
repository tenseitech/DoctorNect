-- =============================================================================
-- DoctorNect RDS Bootstrap: 02_auth_shim.sql
-- Emulates Supabase's auth schema and helper functions over PostgREST JWT claims
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS auth;

-- auth.jwt() extracts request.jwt.claims or request.jwt.claim set by PostgREST
CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim', true), ''),
    NULLIF(current_setting('request.jwt.claims', true), ''),
    '{}'
  )::jsonb;
$$;

-- auth.uid() returns Firebase UID from JWT 'sub' (TEXT; public.users.id is TEXT)
DROP FUNCTION IF EXISTS auth.uid();
CREATE FUNCTION auth.uid()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub', true), ''),
  (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
$$;

-- auth.role() returns the effective database role
CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    NULLIF(auth.jwt() ->> 'role', ''),
    current_setting('role', true)
  );
$$;

-- Grant execution to all roles
GRANT USAGE ON SCHEMA auth TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- SQL Unit Tests for auth shim (Executed in a self-reverting transaction)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_test_claims text := '{"sub":"a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11","role":"authenticated","app_role":"patient","user_role":"patient"}';
  v_uid text;
  v_role text;
  v_jwt jsonb;
BEGIN
  -- Test 1: Empty setting returns empty jsonb and NULL uid
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);

  v_jwt := auth.jwt();
  IF v_jwt IS NULL OR v_jwt != '{}'::jsonb THEN
    RAISE EXCEPTION 'auth.jwt() failed for empty claims: got %', v_jwt;
  END IF;

  v_uid := auth.uid();
  IF v_uid IS NOT NULL THEN
    RAISE EXCEPTION 'auth.uid() failed for empty claims: expected NULL, got %', v_uid;
  END IF;

  -- Test 2: Valid plural claims return correct sub and role
  PERFORM set_config('request.jwt.claims', v_test_claims, true);
  v_uid := auth.uid();
  IF v_uid != 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11' THEN
    RAISE EXCEPTION 'auth.uid() failed: expected a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11, got %', v_uid;
  END IF;

  v_role := auth.role();
  IF v_role != 'authenticated' THEN
    RAISE EXCEPTION 'auth.role() failed: expected authenticated, got %', v_role;
  END IF;

  IF (auth.jwt() ->> 'app_role') != 'patient' THEN
    RAISE EXCEPTION 'auth.jwt()->>app_role failed';
  END IF;

  -- Test 3: Singular claim settings compatibility
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);

  v_uid := auth.uid();
  IF v_uid != 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22' THEN
    RAISE EXCEPTION 'auth.uid() singular failed: expected b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22, got %', v_uid;
  END IF;

  v_role := auth.role();
  IF v_role != 'service_role' THEN
    RAISE EXCEPTION 'auth.role() singular failed: expected service_role, got %', v_role;
  END IF;

  RAISE NOTICE 'auth shim unit tests: ALL PASSED';
END $$;
