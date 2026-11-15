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
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  ELSE
    ALTER ROLE service_role BYPASSRLS;
  END IF;

  -- PostgREST authenticator role (LOGIN, member of anon, authenticated, service_role)
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN NOINHERIT;
  END IF;

  -- App schema migrator / owner role
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_migrator') THEN
    CREATE ROLE app_migrator LOGIN CREATEROLE;
  END IF;

  -- RDS master stand-in role (for local testing/parity with AWS RDS master)
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_superuser') THEN
    CREATE ROLE rds_superuser NOLOGIN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_master') THEN
    CREATE ROLE rds_master LOGIN CREATEROLE CREATEDB;
    GRANT rds_superuser TO rds_master;
  END IF;

  -- AWS RDS master user (production migrator); harmless on local when run as superuser
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doctornect_admin') THEN
    CREATE ROLE doctornect_admin LOGIN CREATEROLE CREATEDB;
    GRANT rds_superuser TO doctornect_admin;
  END IF;
END $$;

-- PG16+: migrator must be able to SET ROLE to app roles for OWNER / policy DDL
DO $$
DECLARE
  migrator text;
BEGIN
  SELECT rolname INTO migrator
  FROM pg_roles
  WHERE rolname IN ('doctornect_admin', 'rds_master', 'app_migrator')
    AND rolcanlogin
  ORDER BY CASE rolname
    WHEN 'doctornect_admin' THEN 1
    WHEN 'rds_master' THEN 2
    ELSE 3
  END
  LIMIT 1;
  IF migrator IS NULL THEN
    migrator := current_user;
  END IF;
  EXECUTE format(
    'GRANT anon, authenticated, service_role, authenticator TO %I WITH ADMIN OPTION, SET TRUE',
    migrator
  );
END $$;

-- Grant role memberships to authenticator so it can switch roles on requests
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;

-- Create extensions in public schema
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
EXCEPTION WHEN insufficient_privilege THEN
  NULL;
END $$;

-- Create publication for realtime compatibility if missing
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

-- Migrator (doctornect_admin) must own publication for ALTER PUBLICATION ADD TABLE in migrations
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doctornect_admin')
     AND EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime OWNER TO doctornect_admin;
  END IF;
EXCEPTION WHEN insufficient_privilege THEN
  NULL;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doctornect_admin') THEN
    GRANT EXECUTE ON FUNCTION pg_stat_statements_reset() TO doctornect_admin;
  END IF;
EXCEPTION WHEN undefined_function OR insufficient_privilege THEN
  NULL;
END $$;


