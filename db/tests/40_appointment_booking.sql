-- Appointment booking / reschedule / cancel through the atomic Postgres RPCs and RLS
-- (replaces the Firestore doctor_slots tests).

SET LOCAL session_replication_role = replica;
SELECT tests.seed('public.doctors', '{"doctor_id":"t_doc_1","owner_uid":"t_doc_uid","name":"Dr A","specialization":"GP","verified":true,"deactivated":false}');
SELECT tests.seed('public.users', '{"id":"t_doc_uid","firebase_uid":"t_doc_uid","role":"doctor","profile_id":"t_doc_1"}');
SELECT tests.seed('public.users', '{"id":"t_p1_uid","firebase_uid":"t_p1_uid","role":"patient","profile_id":"t_p1"}');
SELECT tests.seed('public.users', '{"id":"t_p2_uid","firebase_uid":"t_p2_uid","role":"patient","profile_id":"t_p2"}');
SELECT tests.seed('public.users', '{"id":"t_p3_uid","firebase_uid":"t_p3_uid","role":"patient","profile_id":"t_p3"}');
SELECT tests.seed('public.users', '{"id":"t_p4_uid","firebase_uid":"t_p4_uid","role":"patient","profile_id":"t_p4"}');
SELECT tests.seed('public.patients', '{"patient_id":"t_p1","owner_uid":"t_p1_uid","name":"P1"}');
SELECT tests.seed('public.patients', '{"patient_id":"t_p2","owner_uid":"t_p2_uid","name":"P2"}');
SELECT tests.seed('public.patients', '{"patient_id":"t_p3","owner_uid":"t_p3_uid","name":"P3"}');
SELECT tests.seed('public.patients', '{"patient_id":"t_p4","owner_uid":"t_p4_uid","name":"P4"}');
SET LOCAL session_replication_role = origin;

CREATE OR REPLACE FUNCTION pg_temp.book(p_id text, p_patient text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.book_appointment_atomic(p_id, 't_doc_1', 'x', 'x', 'Name', 30, 'M',
         '2031-01-15 10:00:00+05:30'::timestamptz, '10:00 AM', 'newVisit', NULL, NULL, NULL, 'patient_supabase', p_patient);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.book(text, text) TO authenticated;

SELECT tests.as_user('t_p1_uid');
SELECT tests.check('patient books own slot', (pg_temp.book('t_a1') ->> 'patient_id') = 't_p1');
SELECT tests.check('same appointment id is idempotent for its owner', (pg_temp.book('t_a1') ->> 'appointment_id') = 't_a1');
SELECT tests.expect_error('same patient cannot double-book the slot',
  $q$SELECT pg_temp.book('t_a1_dup')$q$, 'DUPLICATE_PATIENT_BOOKING');
SELECT tests.expect_error('cannot book on behalf of another patient',
  $q$SELECT pg_temp.book('t_a_other', 't_p2')$q$, 'FORBIDDEN');

SELECT tests.as_user('t_p2_uid');
SELECT tests.expect_error('cannot take over another patient''s appointment id',
  $q$SELECT pg_temp.book('t_a1')$q$, 'FORBIDDEN');
SELECT tests.check('second patient books', (pg_temp.book('t_a2') ->> 'patient_id') = 't_p2');
SELECT tests.as_user('t_p3_uid');
SELECT tests.check('third patient books', (pg_temp.book('t_a3') ->> 'patient_id') = 't_p3');
SELECT tests.as_user('t_p4_uid');
SELECT tests.expect_error('slot capacity (3) enforced',
  $q$SELECT pg_temp.book('t_a4')$q$, 'SLOT_CAPACITY_REACHED');

-- Reschedule: only participants.
SELECT tests.as_user('t_p2_uid');
SELECT tests.expect_error('cannot reschedule another patient''s appointment',
  $q$SELECT public.reschedule_appointment_atomic('t_a1', 't_doc_1', DATE '2031-01-16', '11:00 AM', 'patient', NULL)$q$, 'FORBIDDEN');
SELECT tests.as_user('t_p1_uid');
SELECT tests.check('owner reschedules',
  (public.reschedule_appointment_atomic('t_a1', 't_doc_1', DATE '2031-01-16', '11:00 AM', 'patient', NULL) ->> 'ok')::boolean);

-- Cancel: RLS only lets participants update the row.
SELECT tests.as_user('t_p2_uid');
SELECT tests.check('other patient cannot cancel',
  tests.affected($q$UPDATE public.appointments SET patient_status = 'cancelled' WHERE appointment_id = 't_a1'$q$) = 0);
SELECT tests.as_user('t_p1_uid');
SELECT tests.check('owner cancels',
  tests.affected($q$UPDATE public.appointments SET patient_status = 'cancelled' WHERE appointment_id = 't_a1'$q$) = 1);

-- Anonymous callers cannot book.
SET LOCAL ROLE anon;
SELECT tests.expect_error('anon cannot book', $q$SELECT pg_temp.book('t_anon')$q$);

SELECT tests.as_owner();
SELECT tests.check('no double booking: one active row per patient per slot',
  NOT EXISTS (SELECT 1 FROM public.appointments WHERE doctor_id = 't_doc_1' AND patient_status <> 'cancelled'
              GROUP BY patient_id, date_time HAVING count(*) > 1));
SELECT tests.check('slot never exceeds capacity',
  NOT EXISTS (SELECT 1 FROM public.appointments WHERE doctor_id = 't_doc_1' AND patient_status <> 'cancelled'
              GROUP BY date_time HAVING count(*) > 3));

-- 20261125000003: direct PostgREST writes cannot bypass the booking RPC.
SELECT tests.as_user('t_p4_uid');
SELECT tests.expect_error('patient cannot INSERT an appointment directly (capacity bypass)',
  $q$INSERT INTO public.appointments (appointment_id, doctor_id, patient_id, date_time, patient_name, patient_age, patient_gender,
       doctor_name, specialization, slot_label, token_number, visit_type, patient_status, doctor_status)
     VALUES ('t_direct', 't_doc_1', 't_p4', '2031-01-15 10:00:00+05:30', 'x', 1, 'M', 'd', 's', '10:00 AM', 1, 'newVisit', 'confirmed', 'confirmed')$q$);
SELECT tests.as_user('t_p2_uid');
SELECT tests.check('patient cancel via upsert still works',
  tests.affected($q$INSERT INTO public.appointments AS a (appointment_id, doctor_id, patient_id, date_time, patient_name, patient_age, patient_gender,
       doctor_name, specialization, slot_label, token_number, visit_type, patient_status, doctor_status)
     SELECT appointment_id, 't_doc_other', patient_id, date_time + interval '7 days', patient_name, patient_age, patient_gender,
            doctor_name, specialization, slot_label, 1, visit_type, 'cancelled', 'completed'
       FROM public.appointments WHERE appointment_id = 't_a2'
     ON CONFLICT (appointment_id) DO UPDATE SET patient_status = EXCLUDED.patient_status, doctor_id = EXCLUDED.doctor_id,
       date_time = EXCLUDED.date_time, token_number = EXCLUDED.token_number, doctor_status = EXCLUDED.doctor_status$q$) = 1);
SELECT tests.as_owner();
SELECT tests.check('cancel kept slot/doctor columns pinned',
  (SELECT patient_status = 'cancelled' AND doctor_id = 't_doc_1' AND doctor_status <> 'completed' AND date_time = '2031-01-15 10:00:00+05:30'
     FROM public.appointments WHERE appointment_id = 't_a2'));
SELECT tests.as_user('t_doc_uid');
SELECT tests.check('doctor can still add a walk-in',
  tests.affected($q$INSERT INTO public.appointments (appointment_id, doctor_id, patient_id, date_time, patient_name, patient_age, patient_gender,
       doctor_name, specialization, slot_label, token_number, visit_type, patient_status, doctor_status, source)
     VALUES ('t_walkin', 't_doc_1', 't_p4', '2031-01-20 10:00:00+05:30', 'x', 1, 'M', 'd', 's', '10:00 AM', 1, 'newVisit', 'confirmed', 'confirmed', 'walkin')$q$) = 1);
SELECT tests.as_owner();
