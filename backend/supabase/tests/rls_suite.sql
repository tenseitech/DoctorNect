BEGIN;

-- 1. Create temporary table for test results
CREATE TEMP TABLE test_results (
    test_num INT,
    test_name TEXT,
    expected TEXT,
    actual TEXT,
    status TEXT
);
GRANT ALL ON test_results TO authenticated;

-- Synthetic UUIDs for test fixtures
DO $$
DECLARE
    v_doc_a_id TEXT := 'test-doc-a-synth';
    v_doc_b_id TEXT := 'test-doc-b-synth';
    v_doc_unver_id TEXT := 'test-doc-unver-synth';
    v_pat_a_id TEXT := 'test-pat-a-synth';
    v_pat_b_id TEXT := 'test-pat-b-synth';
    v_pat_incomp_id TEXT := 'test-pat-incomp-synth';
    v_pharma_id TEXT := 'test-pharma-synth';

    v_auth_doc_a UUID := '11111111-1111-4111-8111-111111111111';
    v_auth_doc_b UUID := '22222222-2222-4222-8222-222222222222';
    v_auth_doc_unver UUID := '33333333-3333-4333-8333-333333333333';
    v_auth_pat_a UUID := '44444444-4444-4444-8444-444444444444';
    v_auth_pat_b UUID := '55555555-5555-4555-8555-555555555555';
    v_auth_pat_incomp UUID := '66666666-6666-4666-8666-666666666666';
    v_auth_pharma UUID := '77777777-7777-4777-8777-777777777777';

    v_count INT;
    v_has_doc_a BOOLEAN;
    v_has_doc_b BOOLEAN;
    v_has_pat_a BOOLEAN;
    v_has_pat_b BOOLEAN;
    v_sec_blocked BOOLEAN := FALSE;
BEGIN
    -- Disable FK constraint on users temporarily
    ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_id_fkey;

    -- Seed synthetic users
    INSERT INTO users (id, firebase_uid, role, profile_id, display_name, email, mobile, profile_completed, verified, status)
    VALUES 
      (v_auth_doc_a, v_auth_doc_a::text, 'doctor', v_doc_a_id, 'Test Doctor A', 'doc_a@synth.com', '0000000001', TRUE, TRUE, 'approved'),
      (v_auth_doc_b, v_auth_doc_b::text, 'doctor', v_doc_b_id, 'Test Doctor B', 'doc_b@synth.com', '0000000002', TRUE, TRUE, 'approved'),
      (v_auth_doc_unver, v_auth_doc_unver::text, 'doctor', v_doc_unver_id, 'Test Doc Unver', 'doc_unver@synth.com', '0000000003', TRUE, FALSE, 'approved'),
      (v_auth_pat_a, v_auth_pat_a::text, 'patient', v_pat_a_id, 'Test Patient A', 'pat_a@synth.com', '1111111111', TRUE, TRUE, 'approved'),
      (v_auth_pat_b, v_auth_pat_b::text, 'patient', v_pat_b_id, 'Test Patient B', 'pat_b@synth.com', '2222222222', TRUE, TRUE, 'approved'),
      (v_auth_pat_incomp, v_auth_pat_incomp::text, 'patient', v_pat_incomp_id, 'Test Pat Incomp', 'pat_incomp@synth.com', '3333333333', FALSE, FALSE, 'approved'),
      (v_auth_pharma, v_auth_pharma::text, 'medicalStore', v_pharma_id, 'Test Pharmacy', 'pharma@synth.com', '4444444444', TRUE, TRUE, 'approved')
    ON CONFLICT (id) DO NOTHING;

    -- Seed doctors
    INSERT INTO doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated, profile_completed)
    VALUES 
      (v_doc_a_id, v_auth_doc_a, 'Test Doctor A', 'doc_a@synth.com', '0000000001', 'General Medicine', 'MBBS MD', TRUE, FALSE, TRUE),
      (v_doc_b_id, v_auth_doc_b, 'Test Doctor B', 'doc_b@synth.com', '0000000002', 'Cardiology', 'MBBS MD', TRUE, FALSE, TRUE),
      (v_doc_unver_id, v_auth_doc_unver, 'Test Doc Unver', 'doc_unver@synth.com', '0000000003', 'Orthopedics', 'MBBS MS', FALSE, FALSE, TRUE)
    ON CONFLICT (doctor_id) DO NOTHING;

    -- Seed patients
    INSERT INTO patients (patient_id, owner_uid, name, mobile, share_records_with_doctors, profile_completed, verified)
    VALUES 
      (v_pat_a_id, v_auth_pat_a, 'Test Patient A', '1111111111', TRUE, TRUE, TRUE),
      (v_pat_b_id, v_auth_pat_b, 'Test Patient B', '2222222222', TRUE, TRUE, TRUE),
      (v_pat_incomp_id, v_auth_pat_incomp, 'Test Patient Incomplete', '3333333333', TRUE, FALSE, FALSE)
    ON CONFLICT (patient_id) DO NOTHING;

    -- Seed appointments
    INSERT INTO appointments (appointment_id, doctor_id, patient_id, doctor_name, specialization, patient_name, patient_age, patient_gender, date_time, slot_label, visit_type, patient_status, doctor_status)
    VALUES 
      ('apt-synth-a', v_doc_a_id, v_pat_a_id, 'Test Doctor A', 'General Medicine', 'Test Patient A', 30, 'Male', NOW(), '10:00 AM', 'newVisit', 'confirmed', 'confirmed'),
      ('apt-synth-b', v_doc_b_id, v_pat_b_id, 'Test Doctor B', 'Cardiology', 'Test Patient B', 45, 'Female', NOW(), '11:00 AM', 'newVisit', 'confirmed', 'confirmed')
    ON CONFLICT (appointment_id) DO NOTHING;

    -- Seed prescriptions
    INSERT INTO prescriptions (prescription_id, doctor_id, patient_id, appointment_id, patient_name, patient_age)
    VALUES 
      ('rx-synth-a', v_doc_a_id, v_pat_a_id, 'apt-synth-a', 'Test Patient A', 30),
      ('rx-synth-b', v_doc_b_id, v_pat_b_id, 'apt-synth-b', 'Test Patient B', 45)
    ON CONFLICT (prescription_id) DO NOTHING;

END $$;

-- ------------------------------------------------------------------------
-- TEST 1: Doctor Isolation (Doctor A queries patients)
-- ------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results
SELECT 1,
       'Doctor Isolation (Doctor A queries patients)',
       'Sees Patient A only; Patient B blocked',
       'Returned: [' || COALESCE(string_agg(patient_id, ', '), 'NONE') || ']',
       CASE WHEN bool_and(patient_id = 'test-pat-a-synth') AND NOT bool_or(patient_id = 'test-pat-b-synth') THEN 'PASS' ELSE 'FAIL' END
FROM patients
WHERE patient_id IN ('test-pat-a-synth', 'test-pat-b-synth');

-- ------------------------------------------------------------------------
-- TEST 2: Patient Isolation (Patient A queries appointments/prescriptions)
-- ------------------------------------------------------------------------
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "44444444-4444-4444-8444-444444444444", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results
WITH apts AS (
    SELECT array_agg(appointment_id) AS a_ids FROM appointments WHERE appointment_id IN ('apt-synth-a', 'apt-synth-b')
), rxs AS (
    SELECT array_agg(prescription_id) AS r_ids FROM prescriptions WHERE prescription_id IN ('rx-synth-a', 'rx-synth-b')
)
SELECT 2,
       'Patient Isolation (Patient A queries appointments/prescriptions)',
       'Sees own records only; Patient B records blocked',
       'Appointments: ' || COALESCE(a_ids::text, '[]') || ', Rx: ' || COALESCE(r_ids::text, '[]'),
       CASE WHEN ('apt-synth-a' = ANY(a_ids) AND NOT ('apt-synth-b' = ANY(a_ids)))
             AND ('rx-synth-a' = ANY(r_ids) AND NOT ('rx-synth-b' = ANY(r_ids)))
            THEN 'PASS' ELSE 'FAIL' END
FROM apts, rxs;

-- ------------------------------------------------------------------------
-- TEST 3: Cross-Role Blocking (Pharmacy queries patients)
-- ------------------------------------------------------------------------
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "77777777-7777-4777-8777-777777777777", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '77777777-7777-4777-8777-777777777777', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results
SELECT 3,
       'Cross-Role Blocking (Pharmacy queries patients)',
       'Zero rows visible (completely blocked)',
       count(*)::text || ' rows returned',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM patients
WHERE patient_id IN ('test-pat-a-synth', 'test-pat-b-synth');

-- ------------------------------------------------------------------------
-- TEST 4: Admin-Only Table Lockdown (security_events)
-- ------------------------------------------------------------------------
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results
SELECT 4,
       'Admin-Only Table Lockdown (security_events)',
       'Zero rows on SELECT',
       count(*)::text || ' rows returned',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM security_events;

-- ------------------------------------------------------------------------
-- TEST 5: Doctor Verification Gating (Unverified doctor access & discovery)
-- ------------------------------------------------------------------------
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "33333333-3333-4333-8333-333333333333", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

WITH unver_patients AS (
    SELECT count(*) AS cnt FROM patients WHERE patient_id IN ('test-pat-a-synth', 'test-pat-b-synth')
)
INSERT INTO test_results
SELECT 5,
       'Doctor Verification Gating (Unverified doctor access & discovery)',
       'Patient data blocked (0 rows)',
       cnt::text || ' patient rows visible',
       CASE WHEN cnt = 0 THEN 'PASS' ELSE 'FAIL' END
FROM unver_patients;

-- ------------------------------------------------------------------------
-- TEST 6: profileCompleted Gating (profile_completed = false)
-- ------------------------------------------------------------------------
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "66666666-6666-4666-8666-666666666666", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '66666666-6666-4666-8666-666666666666', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

WITH incomp_data AS (
    SELECT (SELECT count(*) FROM appointments WHERE appointment_id IN ('apt-synth-a', 'apt-synth-b')) +
           (SELECT count(*) FROM prescriptions WHERE prescription_id IN ('rx-synth-a', 'rx-synth-b')) AS total_cnt
)
INSERT INTO test_results
SELECT 6,
       'profileCompleted Gating (profile_completed = false querying content)',
       'Blocked from data-tab content (0 rows returned)',
       total_cnt::text || ' rows returned',
       CASE WHEN total_cnt = 0 THEN 'PASS' ELSE 'FAIL' END
FROM incomp_data;

RESET ROLE;

-- Display Results Table
SELECT test_num, test_name, expected, actual, status FROM test_results ORDER BY test_num;

-- Cleanup synthetic test fixtures
DELETE FROM prescriptions WHERE prescription_id IN ('rx-synth-a', 'rx-synth-b');
DELETE FROM appointments WHERE appointment_id IN ('apt-synth-a', 'apt-synth-b');
DELETE FROM patients WHERE patient_id IN ('test-pat-a-synth', 'test-pat-b-synth', 'test-pat-incomp-synth');
DELETE FROM doctors WHERE doctor_id IN ('test-doc-a-synth', 'test-doc-b-synth', 'test-doc-unver-synth');
DELETE FROM users WHERE id IN (
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  '66666666-6666-4666-8666-666666666666',
  '77777777-7777-4777-8777-777777777777'
);

-- Restore FK constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_id_fkey'
  ) THEN
    ALTER TABLE public.users
    ADD CONSTRAINT users_id_fkey
    FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
  END IF;
END $$;

ROLLBACK;
