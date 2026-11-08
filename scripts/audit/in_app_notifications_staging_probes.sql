-- STAGING ONLY — apply db/proposed/20261103000016_proposed_in_app_notifications_supabase.sql
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text, role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', sub, 'role', role)::text, true);
  PERFORM set_config('role', role, true);
END;
$$;

-- Fixture: notification n_staging_1 recipient_uid = uid_recipient (firebase) or users.id mapping.

RESET role;
SET LOCAL role service_role;

DO $$
BEGIN
  PERFORM public.patch_in_app_notification_server(
    p_notification_id := 'n_staging_1',
    p_title := 'server patch',
    p_category := 'ops'
  );
  RAISE NOTICE 'PASS [a_service_role_patch_rpc]';
END;
$$;

SELECT pg_temp.set_jwt('uid_recipient');
SET LOCAL role authenticated;

DO $$
BEGIN
  UPDATE public.in_app_notifications SET title = 'hacked' WHERE notification_id = 'n_staging_1';
  RAISE EXCEPTION 'FAIL [b_recipient_title_patch]: should be rejected';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%recipient may only change is_read%' THEN
      RAISE;
    END IF;
    RAISE NOTICE 'PASS [b_recipient_title_patch]: %', SQLERRM;
END;
$$;

DO $$
BEGIN
  UPDATE public.in_app_notifications SET is_read = true WHERE notification_id = 'n_staging_1';
  RAISE NOTICE 'PASS [c_recipient_updates_is_read]';
END;
$$;

DO $$
BEGIN
  PERFORM public.reconcile_in_app_notification_for_recipient(
    'n_staging_1',
    'reconciled under jwt',
    'body refresh'
  );
  RAISE NOTICE 'PASS [d_security_definer_reconcile_under_client_jwt]';
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL [d_security_definer_reconcile_under_client_jwt]: %', SQLERRM;
END;
$$;

ROLLBACK;
