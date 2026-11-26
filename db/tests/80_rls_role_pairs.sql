-- RLS matrix: what each role can and cannot read about a patient (test gap, PROJECT_ANALYSIS.md).
-- Seeds one patient (A) with a record, appointment, prescription, lab booking and pharmacy delivery,
-- plus every other role, then checks visibility per role pair. Read-only checks (SELECT counts).

SET LOCAL session_replication_role = replica;
-- Patient A and B
SELECT tests.seed('public.users', '{"id":"m_pa_uid","firebase_uid":"m_pa_uid","role":"patient","profile_id":"m_pa"}');
SELECT tests.seed('public.users', '{"id":"m_pb_uid","firebase_uid":"m_pb_uid","role":"patient","profile_id":"m_pb"}');
SELECT tests.seed('public.patients', '{"patient_id":"m_pa","owner_uid":"m_pa_uid","name":"PA"}');
SELECT tests.seed('public.patients', '{"patient_id":"m_pb","owner_uid":"m_pb_uid","name":"PB"}');
-- Doctor with an appointment with A (care relationship) and a doctor without one
SELECT tests.seed('public.users', '{"id":"m_d1_uid","firebase_uid":"m_d1_uid","role":"doctor","profile_id":"m_d1"}');
SELECT tests.seed('public.users', '{"id":"m_d2_uid","firebase_uid":"m_d2_uid","role":"doctor","profile_id":"m_d2"}');
SELECT tests.seed('public.doctors', '{"doctor_id":"m_d1","owner_uid":"m_d1_uid","name":"D1","verified":true,"deactivated":false}');
SELECT tests.seed('public.doctors', '{"doctor_id":"m_d2","owner_uid":"m_d2_uid","name":"D2","verified":true,"deactivated":false}');
-- Lab with A's booking, another lab; pharmacy with A's delivery, another pharmacy; ambulance
SELECT tests.seed('public.users', '{"id":"m_l1_uid","firebase_uid":"m_l1_uid","role":"lab","profile_id":"m_l1"}');
SELECT tests.seed('public.users', '{"id":"m_l2_uid","firebase_uid":"m_l2_uid","role":"lab","profile_id":"m_l2"}');
SELECT tests.seed('public.labs', '{"lab_id":"m_l1","owner_uid":"m_l1_uid"}');
SELECT tests.seed('public.labs', '{"lab_id":"m_l2","owner_uid":"m_l2_uid"}');
SELECT tests.seed('public.users', '{"id":"m_s1_uid","firebase_uid":"m_s1_uid","role":"medicalStore","profile_id":"m_s1"}');
SELECT tests.seed('public.users', '{"id":"m_s2_uid","firebase_uid":"m_s2_uid","role":"medicalStore","profile_id":"m_s2"}');
SELECT tests.seed('public.medical_stores', '{"store_id":"m_s1","owner_uid":"m_s1_uid"}');
SELECT tests.seed('public.medical_stores', '{"store_id":"m_s2","owner_uid":"m_s2_uid"}');
SELECT tests.seed('public.users', '{"id":"m_a_uid","firebase_uid":"m_a_uid","role":"ambulance","profile_id":"m_a"}');
SELECT tests.seed('public.ambulances', '{"ambulance_id":"m_a","auth_uid":"m_a_uid"}');
-- A's data
SELECT tests.seed('public.health_records', '{"record_id":"m_hr","patient_id":"m_pa"}');
SELECT tests.seed('public.appointments', '{"appointment_id":"m_ap","patient_id":"m_pa","doctor_id":"m_d1","patient_status":"confirmed","doctor_status":"confirmed"}');
SELECT tests.seed('public.prescriptions', '{"prescription_id":"m_rx","patient_id":"m_pa","doctor_id":"m_d1"}');
SELECT tests.seed('public.lab_bookings', '{"booking_id":"m_lb","patient_id":"m_pa","lab_id":"m_l1"}');
SELECT tests.seed('public.pharmacy_deliveries', '{"delivery_id":"m_pd","patient_id":"m_pa","store_id":"m_s1","prescription_id":"m_rx","doctor_id":"m_d1"}');
SET LOCAL session_replication_role = origin;

CREATE OR REPLACE FUNCTION pg_temp.n(p_sql text) RETURNS int LANGUAGE plpgsql AS $$
DECLARE v int; BEGIN EXECUTE 'SELECT count(*) FROM (' || p_sql || ') q' INTO v; RETURN v; END $$;
GRANT EXECUTE ON FUNCTION pg_temp.n(text) TO authenticated, anon;

-- Patient A sees own data
SELECT tests.as_user('m_pa_uid');
SELECT tests.check('patient sees own health record', pg_temp.n($q$SELECT 1 FROM public.health_records WHERE record_id='m_hr'$q$) = 1);
SELECT tests.check('patient sees own appointment', pg_temp.n($q$SELECT 1 FROM public.appointments WHERE appointment_id='m_ap'$q$) = 1);
SELECT tests.check('patient sees own prescription', pg_temp.n($q$SELECT 1 FROM public.prescriptions WHERE prescription_id='m_rx'$q$) = 1);
SELECT tests.check('patient sees own lab booking', pg_temp.n($q$SELECT 1 FROM public.lab_bookings WHERE booking_id='m_lb'$q$) = 1);

-- Patient B sees none of A's data
SELECT tests.as_user('m_pb_uid');
SELECT tests.check('other patient: no health record', pg_temp.n($q$SELECT 1 FROM public.health_records WHERE patient_id='m_pa'$q$) = 0);
SELECT tests.check('other patient: no appointment', pg_temp.n($q$SELECT 1 FROM public.appointments WHERE patient_id='m_pa'$q$) = 0);
SELECT tests.check('other patient: no prescription', pg_temp.n($q$SELECT 1 FROM public.prescriptions WHERE patient_id='m_pa'$q$) = 0);
SELECT tests.check('other patient: no lab booking', pg_temp.n($q$SELECT 1 FROM public.lab_bookings WHERE patient_id='m_pa'$q$) = 0);
SELECT tests.check('other patient: no delivery', pg_temp.n($q$SELECT 1 FROM public.pharmacy_deliveries WHERE patient_id='m_pa'$q$) = 0);

-- Doctor without a care relationship sees none of A's clinical data
SELECT tests.as_user('m_d2_uid');
SELECT tests.check('unrelated doctor: no health record', pg_temp.n($q$SELECT 1 FROM public.health_records WHERE patient_id='m_pa'$q$) = 0);
SELECT tests.check('unrelated doctor: no appointment', pg_temp.n($q$SELECT 1 FROM public.appointments WHERE patient_id='m_pa'$q$) = 0);
SELECT tests.check('unrelated doctor: no prescription', pg_temp.n($q$SELECT 1 FROM public.prescriptions WHERE patient_id='m_pa'$q$) = 0);

-- Treating doctor sees the appointment and prescription he wrote
SELECT tests.as_user('m_d1_uid');
SELECT tests.check('treating doctor sees the appointment', pg_temp.n($q$SELECT 1 FROM public.appointments WHERE appointment_id='m_ap'$q$) = 1);
SELECT tests.check('treating doctor sees own prescription', pg_temp.n($q$SELECT 1 FROM public.prescriptions WHERE prescription_id='m_rx'$q$) = 1);

-- Labs: only the booked lab sees the booking; no lab sees health records or prescriptions
SELECT tests.as_user('m_l1_uid');
SELECT tests.check('booked lab sees the booking', pg_temp.n($q$SELECT 1 FROM public.lab_bookings WHERE booking_id='m_lb'$q$) = 1);
SELECT tests.check('lab: no health records', pg_temp.n($q$SELECT 1 FROM public.health_records WHERE patient_id='m_pa'$q$) = 0);
SELECT tests.as_user('m_l2_uid');
SELECT tests.check('other lab: no booking', pg_temp.n($q$SELECT 1 FROM public.lab_bookings WHERE patient_id='m_pa'$q$) = 0);

-- Pharmacies: only the assigned store sees the delivery; no store sees health records
SELECT tests.as_user('m_s1_uid');
SELECT tests.check('assigned pharmacy sees the delivery', pg_temp.n($q$SELECT 1 FROM public.pharmacy_deliveries WHERE delivery_id='m_pd'$q$) = 1);
SELECT tests.check('pharmacy: no health records', pg_temp.n($q$SELECT 1 FROM public.health_records WHERE patient_id='m_pa'$q$) = 0);
SELECT tests.as_user('m_s2_uid');
SELECT tests.check('other pharmacy: no delivery', pg_temp.n($q$SELECT 1 FROM public.pharmacy_deliveries WHERE patient_id='m_pa'$q$) = 0);

-- Ambulance sees no clinical data
SELECT tests.as_user('m_a_uid');
SELECT tests.check('ambulance: no health records', pg_temp.n($q$SELECT 1 FROM public.health_records WHERE patient_id='m_pa'$q$) = 0);
SELECT tests.check('ambulance: no prescriptions', pg_temp.n($q$SELECT 1 FROM public.prescriptions WHERE patient_id='m_pa'$q$) = 0);
SELECT tests.check('ambulance: no lab bookings', pg_temp.n($q$SELECT 1 FROM public.lab_bookings WHERE patient_id='m_pa'$q$) = 0);

-- Anonymous callers have no table privilege at all on clinical data (stronger than RLS)
SET LOCAL ROLE anon;
SELECT tests.expect_error('anon: health_records not granted', $q$SELECT 1 FROM public.health_records$q$, 'permission denied');
SELECT tests.expect_error('anon: patients not granted', $q$SELECT 1 FROM public.patients$q$, 'permission denied');
RESET ROLE;
