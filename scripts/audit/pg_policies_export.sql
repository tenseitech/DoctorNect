-- Run on staging (read-only OK) and save CSV output for pg_policies_to_matrix.js
-- psql "$STAGING_SUPABASE_DB_URL" -f scripts/audit/pg_policies_export.sql -o pg_policies.csv --csv

SELECT
  schemaname,
  tablename,
  policyname,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname, cmd;
