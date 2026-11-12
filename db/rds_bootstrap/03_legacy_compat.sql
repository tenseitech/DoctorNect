-- =============================================================================
-- DoctorNect RDS Bootstrap: 03_legacy_compat.sql
-- Legacy compatibility prerequisites for initial Supabase migrations
-- =============================================================================

-- Legacy supabase_admin role stub for migrations referencing Supabase default privileges (e.g. 20260930000001)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    CREATE ROLE supabase_admin NOLOGIN;
  END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS auth;

-- Legacy auth.users stub required for early migration foreign keys (e.g. 20260923000001)
CREATE TABLE IF NOT EXISTS auth.users (
  instance_id uuid,
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  aud varchar(255),
  role varchar(255),
  email varchar(255) UNIQUE,
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  invited_at timestamptz,
  confirmation_token varchar(255),
  confirmation_sent_at timestamptz,
  recovery_token varchar(255),
  recovery_sent_at timestamptz,
  email_change_token_new varchar(255),
  email_change varchar(255),
  email_change_sent_at timestamptz,
  last_sign_in_at timestamptz,
  raw_app_meta_data jsonb DEFAULT '{}'::jsonb,
  raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
  is_super_admin boolean,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  phone text,
  phone_confirmed_at timestamptz,
  phone_change text,
  phone_change_token varchar(255),
  phone_change_sent_at timestamptz,
  confirmed_at timestamptz,
  email_change_token_current varchar(255),
  email_change_confirm_status smallint,
  banned_until timestamptz,
  reauthentication_token varchar(255),
  reauthentication_sent_at timestamptz,
  is_sso_user boolean DEFAULT false,
  deleted_at timestamptz,
  is_anonymous boolean DEFAULT false
);

-- Legacy private schema created upfront to allow private.* helpers
CREATE SCHEMA IF NOT EXISTS private;

-- Permissions
GRANT USAGE ON SCHEMA auth TO PUBLIC, anon, authenticated, service_role;
GRANT ALL ON auth.users TO postgres, service_role;
GRANT SELECT ON auth.users TO authenticated;
GRANT USAGE ON SCHEMA private TO PUBLIC, anon, authenticated, service_role;



