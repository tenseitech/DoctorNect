-- Demo: SECURITY DEFINER trigger with current_user IN ('postgres',...) never restricts the invoker.
-- Run in a throwaway DB; ROLLBACK at end.

BEGIN;

CREATE TABLE IF NOT EXISTS pg_temp.demo_rows (
  id text PRIMARY KEY,
  title text NOT NULL,
  is_read boolean NOT NULL DEFAULT false
);

INSERT INTO pg_temp.demo_rows (id, title) VALUES ('n1', 'orig');

CREATE OR REPLACE FUNCTION pg_temp.trigger_definer_broken()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp
AS $$
BEGIN
  IF current_user IN ('postgres', 'supabase_admin') THEN
    RETURN NEW;
  END IF;
  IF NEW.title IS DISTINCT FROM OLD.title THEN
    RAISE EXCEPTION 'title blocked';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_broken
  BEFORE UPDATE ON pg_temp.demo_rows
  FOR EACH ROW
  EXECUTE FUNCTION pg_temp.trigger_definer_broken();

DO $$
BEGIN
  UPDATE pg_temp.demo_rows SET title = 'hacked' WHERE id = 'n1';
  RAISE NOTICE 'BROKEN DEFINER: recipient changed title — trigger did NOT restrict';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'BROKEN DEFINER: blocked (unexpected): %', SQLERRM;
END;
$$;

DROP TRIGGER trg_broken ON pg_temp.demo_rows;

CREATE OR REPLACE FUNCTION pg_temp.trigger_invoker_fixed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_temp
AS $$
BEGIN
  IF session_user IN ('postgres', 'supabase_admin', 'service_role') THEN
    RETURN NEW;
  END IF;
  IF NEW.title IS DISTINCT FROM OLD.title THEN
    RAISE EXCEPTION 'title blocked';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_fixed
  BEFORE UPDATE ON pg_temp.demo_rows
  FOR EACH ROW
  EXECUTE FUNCTION pg_temp.trigger_invoker_fixed();

DO $$
BEGIN
  UPDATE pg_temp.demo_rows SET title = 'hacked2' WHERE id = 'n1';
  RAISE EXCEPTION 'INVOKER: should have blocked title';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'INVOKER OK: %', SQLERRM;
END;
$$;

ROLLBACK;
