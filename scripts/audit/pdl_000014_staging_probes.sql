-- STAGING ONLY — compare deployed pdl_select vs proposed 000014.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text, role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', sub, 'role', role)::text, true);
  PERFORM set_config('role', role, true);
END;
$$;

-- Patient with owner_uid mapping (patient_id <> firebase uid): sees own link row
SELECT pg_temp.set_jwt('uid_patient_owner');
SET LOCAL role authenticated;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.patient_doctor_links pdl
    JOIN public.patients p ON p.patient_id = pdl.patient_id
    WHERE p.owner_uid = 'uid_patient_owner'
  ) THEN
    RAISE EXCEPTION 'FAIL [pdl_patient_owner_uid]: no rows visible';
  END IF;
  RAISE NOTICE 'PASS [pdl_patient_owner_uid]';
END;
$$;

-- Unverified doctor reads own doctors row (onboarding)
SELECT pg_temp.set_jwt('uid_doc_unverified');
SET LOCAL role authenticated;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.doctors d
    WHERE d.owner_uid = 'uid_doc_unverified'
  ) THEN
    RAISE EXCEPTION 'FAIL [doctors_select_unverified_self]';
  END IF;
  RAISE NOTICE 'PASS [doctors_select_unverified_self]';
END;
$$;

ROLLBACK;
