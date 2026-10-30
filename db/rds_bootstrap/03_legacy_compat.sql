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

-- Legacy cron schema and functions for environments lacking native pg_cron
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    CREATE SCHEMA IF NOT EXISTS cron;
    CREATE TABLE IF NOT EXISTS cron.job (
        jobid serial PRIMARY KEY,
        schedule text NOT NULL,
        command text NOT NULL,
        nodename text DEFAULT 'localhost',
        nodeport integer DEFAULT 5432,
        database text DEFAULT current_database(),
        username text DEFAULT current_user,
        active boolean DEFAULT true,
        jobname text UNIQUE
    );
    CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text)
    RETURNS bigint LANGUAGE plpgsql AS $f$
    DECLARE v_id bigint;
    BEGIN
        INSERT INTO cron.job (jobname, schedule, command)
        VALUES (job_name, schedule, command)
        ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
        RETURNING jobid INTO v_id;
        RETURN v_id;
    END;
    $f$;
    CREATE OR REPLACE FUNCTION cron.unschedule(job_name text)
    RETURNS boolean LANGUAGE plpgsql AS $f$
    BEGIN
        DELETE FROM cron.job WHERE jobname = job_name;
        RETURN FOUND;
    END;
    $f$;
    GRANT USAGE ON SCHEMA cron TO PUBLIC, anon, authenticated, service_role;
    GRANT ALL ON ALL TABLES IN SCHEMA cron TO PUBLIC, anon, authenticated, service_role;
    GRANT ALL ON ALL FUNCTIONS IN SCHEMA cron TO PUBLIC, anon, authenticated, service_role;
  END IF;
END $$;

-- System config table pre-creation with master policy so non-superuser migrations can seed it
CREATE TABLE IF NOT EXISTS public.system_config (
    config_key VARCHAR(64) PRIMARY KEY,
    config_value JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'system_config' AND policyname = 'system_config_migrator_bypass'
  ) THEN
    CREATE POLICY "system_config_migrator_bypass" ON public.system_config
    FOR ALL TO PUBLIC
    USING (current_user IN ('rds_master', 'app_migrator', 'postgres') OR session_user IN ('rds_master', 'app_migrator', 'postgres'))
    WITH CHECK (current_user IN ('rds_master', 'app_migrator', 'postgres') OR session_user IN ('rds_master', 'app_migrator', 'postgres'));
  END IF;
END $$;

-- doctor_directory_updates table pre-creation with master/admin policy so non-superuser triggers can update it under FORCE ROW LEVEL SECURITY
CREATE TABLE IF NOT EXISTS public.doctor_directory_updates (
    id VARCHAR(64) PRIMARY KEY,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'doctor_directory_updates' AND policyname = 'doctor_directory_updates_admin_write'
  ) THEN
    CREATE POLICY "doctor_directory_updates_admin_write" ON public.doctor_directory_updates
    FOR ALL TO PUBLIC
    USING (current_user IN ('rds_master', 'app_migrator', 'postgres', 'service_role') OR session_user IN ('rds_master', 'app_migrator', 'postgres', 'service_role'))
    WITH CHECK (current_user IN ('rds_master', 'app_migrator', 'postgres', 'service_role') OR session_user IN ('rds_master', 'app_migrator', 'postgres', 'service_role'));
  END IF;
END $$;


