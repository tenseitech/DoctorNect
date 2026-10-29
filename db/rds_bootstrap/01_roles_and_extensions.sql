-- =============================================================================
-- DoctorNect RDS Bootstrap: 01_roles_and_extensions.sql
-- Idempotent setup of runtime PostgREST roles and allowed PostgreSQL extensions
-- =============================================================================

DO $$
BEGIN
  -- NOLOGIN application roles
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN;
  END IF;

  -- PostgREST authenticator role (LOGIN, member of anon, authenticated, service_role)
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN NOINHERIT;
  END IF;

  -- App schema migrator / owner role
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_migrator') THEN
    CREATE ROLE app_migrator LOGIN CREATEROLE;
  END IF;
END $$;

-- Grant role memberships to authenticator so it can switch roles on requests
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;

-- Create extensions in public schema
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create publication for realtime compatibility if missing
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

-- Provide cron schema, jobs table, and schedule function if native pg_cron is not loaded
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    CREATE SCHEMA cron;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS cron.job (
  jobid bigserial PRIMARY KEY,
  schedule text NOT NULL,
  command text NOT NULL,
  nodename text DEFAULT 'localhost',
  nodeport integer DEFAULT 5432,
  database text DEFAULT current_database(),
  username text DEFAULT CURRENT_USER,
  active boolean DEFAULT true,
  jobname text UNIQUE
);

CREATE OR REPLACE FUNCTION cron.schedule(name text, schedule text, command text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  v_jobid bigint;
BEGIN
  INSERT INTO cron.job (jobname, schedule, command)
  VALUES (name, schedule, command)
  ON CONFLICT (jobname) DO UPDATE SET
    schedule = EXCLUDED.schedule,
    command = EXCLUDED.command,
    active = true
  RETURNING jobid INTO v_jobid;
  RETURN v_jobid;
END;
$$;

CREATE OR REPLACE FUNCTION cron.schedule(schedule text, command text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  v_jobid bigint;
BEGIN
  INSERT INTO cron.job (schedule, command)
  VALUES (schedule, command)
  RETURNING jobid INTO v_jobid;
  RETURN v_jobid;
END;
$$;
