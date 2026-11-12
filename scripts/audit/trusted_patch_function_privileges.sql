-- Run on STAGING (or any env) after applying 000016.
-- Lists functions whose body mentions app.in_app_notifications_trusted_patch
-- and whether anon/authenticated may EXECUTE them (should be false for patch RPC).

SELECT
  n.nspname AS schema,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS args,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_may_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_may_execute,
  has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_may_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.prosrc ILIKE '%app.in_app_notifications_trusted_patch%'
ORDER BY 1, 2, 3;
