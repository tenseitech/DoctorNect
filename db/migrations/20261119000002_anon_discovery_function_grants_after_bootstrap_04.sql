-- Bootstrap 04 ends with REVOKE ALL ROUTINES FROM anon; re-assert discovery EXECUTE (idempotent).

GRANT EXECUTE ON FUNCTION public.doctor_directory_rows() TO anon, authenticated, service_role;