-- STAGING ONLY — exercise proposed 000015 RPCs after manual apply on a branch DB.
-- Expect failures/success as commented; wrap in BEGIN...ROLLBACK for dry run.

BEGIN;

-- Seed fixtures (replace IDs/uids with staging values):
-- lab_booking lb_test_1 patient p1 lab l_verified status inAnalysis
-- user uid_attacker (no relation), uid_patient, uid_lab

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', sub, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

-- 1) Unauthorized user rejected
SELECT pg_temp.set_jwt('uid-attacker');
SET LOCAL role authenticated;
DO $$
BEGIN
  PERFORM public.update_lab_booking_status('lb_test_1', 'completed', NULL, NULL);
  RAISE EXCEPTION 'FAIL: unauthorized should not succeed';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%Unauthorized%' AND SQLERRM NOT LIKE '%42501%' THEN
    RAISE;
  END IF;
  RAISE NOTICE 'PASS: unauthorized booking update rejected';
END;
$$;

-- 2) Patient cannot set report key
SELECT pg_temp.set_jwt('uid-patient');
SET LOCAL role authenticated;
DO $$
BEGIN
  PERFORM public.update_lab_booking_status(
    'lb_test_1', 'completed', NULL,
    'lab_reports/p1/lb_test_1/report.pdf'
  );
  RAISE EXCEPTION 'FAIL: patient must not set report key';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%Patients cannot set report storage key%' THEN
    RAISE;
  END IF;
  RAISE NOTICE 'PASS: patient report key rejected';
END;
$$;

-- 3) Wrong prefix rejected (lab)
SELECT pg_temp.set_jwt('uid-lab-verified');
SET LOCAL role authenticated;
DO $$
BEGIN
  PERFORM public.update_lab_booking_status(
    'lb_test_1', 'completed', NULL,
    'lab_reports/wrong/lb_test_1/report.pdf'
  );
  RAISE EXCEPTION 'FAIL: wrong prefix should be rejected';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%Invalid report_storage_key%' THEN
    RAISE;
  END IF;
  RAISE NOTICE 'PASS: wrong-prefix key rejected';
END;
$$;

-- 4) Valid lab succeeds (when booking inAnalysis)
SELECT pg_temp.set_jwt('uid-lab-verified');
SET LOCAL role authenticated;
DO $$
DECLARE
  v jsonb;
BEGIN
  v := public.update_lab_booking_status(
    'lb_test_1', 'completed', NULL,
    'lab_reports/p1/lb_test_1/uuid.pdf'
  );
  IF (v->>'success')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: valid lab complete expected success';
  END IF;
  RAISE NOTICE 'PASS: valid lab report key + completed';
END;
$$;

ROLLBACK;
