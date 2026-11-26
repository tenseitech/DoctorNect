-- Staging Supabase: read-only role for local audit scripts only
-- (verify_demo_login_chain_readonly.js, post_deploy_demo_routing_verify.js, etc.)
-- Run once in Supabase SQL Editor as postgres (or via migration). Do not use on RDS.

BEGIN;

CREATE ROLE doctornect_audit LOGIN PASSWORD 'REPLACE_WITH_STRONG_PASSWORD';

GRANT CONNECT ON DATABASE postgres TO doctornect_audit;
GRANT USAGE ON SCHEMA public TO doctornect_audit;

-- Minimum surface: demo login chain checks read public.users only
GRANT SELECT ON TABLE public.users TO doctornect_audit;

-- Optional: confirm absence of demo rows in other tables without writes
-- REVOKE ALL ON ALL TABLES IN SCHEMA public FROM doctornect_audit;
-- GRANT SELECT ON TABLE public.users TO doctornect_audit;

COMMIT;

-- Connection string for root .env STAGING_SUPABASE_DB_URL (pooler, sslmode=require):
-- postgresql://doctornect_audit.[PROJECT_REF]:[PASSWORD]@aws-0-ap-south-1.pooler.supabase.com:5432/postgres?sslmode=require