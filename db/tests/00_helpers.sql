-- DoctorNect SQL test helpers. Loaded by scripts/db/run_sql_tests.js before each test file,
-- inside the same transaction (everything is rolled back afterwards).

CREATE SCHEMA IF NOT EXISTS tests;
GRANT USAGE ON SCHEMA tests TO PUBLIC;

-- Insert a row, filling every NOT NULL column without a default that the caller did not supply
-- with a type-appropriate dummy value. Keeps seeds stable when the schema gains columns.
CREATE OR REPLACE FUNCTION tests.seed(p_table regclass, p_data jsonb)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_data jsonb := p_data;
    c record;
    v_val jsonb;
    v_cols text;
BEGIN
    FOR c IN
        SELECT a.attname, t.typname, t.typcategory, t.oid AS typoid, a.atttypmod
          FROM pg_attribute a
          JOIN pg_type t ON t.oid = a.atttypid
         WHERE a.attrelid = p_table
           AND a.attnum > 0
           AND NOT a.attisdropped
           AND a.attnotnull
           AND a.attidentity = ''
           AND a.attgenerated = ''
           AND NOT EXISTS (SELECT 1 FROM pg_attrdef d WHERE d.adrelid = a.attrelid AND d.adnum = a.attnum)
    LOOP
        CONTINUE WHEN v_data ? c.attname;
        v_val := CASE
            WHEN c.typname IN ('uuid') THEN to_jsonb(gen_random_uuid()::text)
            WHEN c.typname IN ('json', 'jsonb') THEN '{}'::jsonb
            WHEN c.typcategory = 'A' THEN '[]'::jsonb
            WHEN c.typcategory = 'B' THEN 'false'::jsonb
            WHEN c.typcategory = 'N' THEN '1'::jsonb
            WHEN c.typcategory = 'D' THEN to_jsonb(now())
            WHEN c.typcategory = 'E' THEN to_jsonb((SELECT enumlabel FROM pg_enum WHERE enumtypid = c.typoid ORDER BY enumsortorder LIMIT 1))
            WHEN c.typcategory = 'S' THEN to_jsonb(left('t' || md5(random()::text), CASE WHEN c.atttypmod > 4 THEN least(c.atttypmod - 4, 12) ELSE 12 END))
            ELSE NULL
        END;
        IF v_val IS NULL THEN
            RAISE EXCEPTION 'tests.seed: cannot invent a value for %.% (%)', p_table, c.attname, c.typname;
        END IF;
        v_data := v_data || jsonb_build_object(c.attname, v_val);
    END LOOP;

    SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(v_data) AS k;
    EXECUTE format('INSERT INTO %s (%s) SELECT %s FROM jsonb_populate_record(NULL::%s, $1)',
                   p_table, v_cols, v_cols, p_table)
      USING v_data;
END;
$$;

-- Act as a PostgREST caller. Claims are transaction-local.
CREATE OR REPLACE FUNCTION tests.as_user(p_uid text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION tests.as_service()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
    PERFORM set_config('role', 'service_role', true);
END;
$$;

CREATE OR REPLACE FUNCTION tests.as_owner()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('role', 'none', true);
    PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

-- Run SQL as the current role; fail unless it raises an error whose SQLSTATE starts with
-- p_state (or whose message contains p_state when p_state is not a 5-char state prefix).
CREATE OR REPLACE FUNCTION tests.expect_error(p_label text, p_sql text, p_state text DEFAULT '42501')
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_state text;
    v_msg text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        IF v_state LIKE p_state || '%' OR position(p_state IN v_msg) > 0 THEN
            RAISE NOTICE 'ok   %', p_label;
            RETURN;
        END IF;
        RAISE EXCEPTION 'FAIL % : expected % but got % (%)', p_label, p_state, v_state, v_msg;
    END;
    RAISE EXCEPTION 'FAIL % : statement succeeded but should have failed', p_label;
END;
$$;

-- Execute SQL and return the number of affected rows.
CREATE OR REPLACE FUNCTION tests.affected(p_sql text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION tests.check(p_label text, p_cond boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FAIL %', p_label;
    END IF;
    RAISE NOTICE 'ok   %', p_label;
END;
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA tests TO PUBLIC;
