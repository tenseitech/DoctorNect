-- STAGING ONLY — apply db/proposed/20261103000016_proposed_in_app_notifications_supabase.sql
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text, role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', sub, 'role', role)::text, true);
  PERFORM set_config('role', role, true);
END;
$$;

-- Fixture: notification n_staging_1 recipient_uid = uid_recipient; jwt sub matches

SELECT pg_temp.set_jwt('uid_recipient');
SET LOCAL role authenticated;

DO $$
BEGIN
  UPDATE public.in_app_notifications SET is_read = true WHERE notification_id = 'n_staging_1';
  RAISE NOTICE 'PASS [recipient_mark_read]';
END;
$$;

DO $$
BEGIN
  UPDATE public.in_app_notifications SET title = 'hacked' WHERE notification_id = 'n_staging_1';
  RAISE EXCEPTION 'FAIL [recipient_title_patch]: should be rejected';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%recipient may only change is_read%' THEN
      RAISE;
    END IF;
    RAISE NOTICE 'PASS [recipient_title_patch]: %', SQLERRM;
END;
$$;

RESET role;
SET LOCAL role service_role;

DO $$
BEGIN
  UPDATE public.in_app_notifications
  SET title = 'server patch', category = 'ops'
  WHERE notification_id = 'n_staging_1';
  RAISE NOTICE 'PASS [service_role_patch_any_column]';
END;
$$;

-- Probe: SECURITY DEFINER (owner postgres) may patch title while invoked under client JWT.
CREATE OR REPLACE FUNCTION pg_temp.probe_definer_patch_notification_title(p_id text, p_title text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.in_app_notifications SET title = p_title WHERE notification_id = p_id;
END;
$$;

ALTER FUNCTION pg_temp.probe_definer_patch_notification_title(text, text) OWNER TO postgres;

SELECT pg_temp.set_jwt('uid_recipient');
SET LOCAL role authenticated;

DO $$
BEGIN
  PERFORM pg_temp.probe_definer_patch_notification_title('n_staging_1', 'definer patch under jwt');
  RAISE NOTICE 'PASS [security_definer_title_under_client_jwt]';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'FAIL [security_definer_title_under_client_jwt]: %', SQLERRM;
END;
$$;

ROLLBACK;
