-- idempotent: EXECUTE for platform-admin helpers (Supabase default-priv revoke gap after 20260930000001).
-- 20261112000001/02 create these without GRANT EXECUTE; triggers (INVOKER) and users_delete_admin need authenticated.
-- Do not grant anon or rely on bootstrap 04.

DO $grant$
BEGIN
  IF to_regprocedure('private.is_system_admin_user(text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION private.is_system_admin_user(TEXT) FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION private.is_system_admin_user(TEXT) TO authenticated, service_role;
  END IF;

  IF to_regprocedure('private.trg_users_protect_system_admin()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION private.trg_users_protect_system_admin() FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION private.trg_users_protect_system_admin() TO authenticated, service_role;
  END IF;

  IF to_regprocedure('private.trg_users_protect_system_admin_delete()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION private.trg_users_protect_system_admin_delete() FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION private.trg_users_protect_system_admin_delete() TO authenticated, service_role;
  END IF;
END;
$grant$;