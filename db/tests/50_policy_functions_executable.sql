-- Regression for 20261125000002: no RLS policy may call a function the policy's role cannot
-- EXECUTE (PostgreSQL then fails the whole query, not just that OR branch).

SELECT tests.as_user('t_nobody_uid');
DO $$
DECLARE
    r record;
    v_state text;
    v_msg text;
    v_bad text := '';
BEGIN
    FOR r IN
        SELECT DISTINCT p.schemaname, p.tablename
          FROM pg_policies p
         WHERE p.schemaname = 'public'
           AND ('authenticated' = ANY (p.roles) OR 'public' = ANY (p.roles))
           AND p.cmd IN ('SELECT', 'ALL')
           AND has_table_privilege('authenticated', format('%I.%I', p.schemaname, p.tablename), 'SELECT')
    LOOP
        BEGIN
            EXECUTE format('SELECT count(*) FROM %I.%I', r.schemaname, r.tablename);
        EXCEPTION WHEN insufficient_privilege THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            v_bad := v_bad || format(E'\n  %s: %s', r.tablename, v_msg);
        END;
    END LOOP;
    IF v_bad <> '' THEN
        RAISE EXCEPTION 'FAIL authenticated SELECT raises permission errors:%', v_bad;
    END IF;
    RAISE NOTICE 'ok   every authenticated-readable table evaluates its policies';
END;
$$;
SELECT tests.as_owner();
