-- RDS replay override for 20260923000002_doctornect_rls.sql
-- Skipped: auth.uid() RETURNS text on RDS shim vs UUID columns (42883 uuid = text).
-- RLS and helpers applied in 20261020000001_consolidated_firebase_schema_and_rls.sql.
SELECT 1 AS rds_replay_skip_doctornect_rls;