-- reschedule_appointment_atomic (20261126000001): real slot time, same capacity rule as booking,
-- no re-opening closed appointments, no past dates.

SET LOCAL session_replication_role = replica;
SELECT tests.seed('public.doctors', '{"doctor_id":"r_doc_1","owner_uid":"r_doc_uid","name":"Dr R","specialization":"GP","verified":true,"deactivated":false}');
SELECT tests.seed('public.users', '{"id":"r_doc_uid","firebase_uid":"r_doc_uid","role":"doctor","profile_id":"r_doc_1"}');
SELECT tests.seed('public.users', '{"id":"r_p1_uid","firebase_uid":"r_p1_uid","role":"patient","profile_id":"r_p1"}');
SELECT tests.seed('public.users', '{"id":"r_p2_uid","firebase_uid":"r_p2_uid","role":"patient","profile_id":"r_p2"}');
SELECT tests.seed('public.users', '{"id":"r_p3_uid","firebase_uid":"r_p3_uid","role":"patient","profile_id":"r_p3"}');
SELECT tests.seed('public.users', '{"id":"r_p4_uid","firebase_uid":"r_p4_uid","role":"patient","profile_id":"r_p4"}');
SELECT tests.seed('public.patients', '{"patient_id":"r_p1","owner_uid":"r_p1_uid","name":"P1"}');
SELECT tests.seed('public.patients', '{"patient_id":"r_p2","owner_uid":"r_p2_uid","name":"P2"}');
SELECT tests.seed('public.patients', '{"patient_id":"r_p3","owner_uid":"r_p3_uid","name":"P3"}');
SELECT tests.seed('public.patients', '{"patient_id":"r_p4","owner_uid":"r_p4_uid","name":"P4"}');
SET LOCAL session_replication_role = origin;

CREATE OR REPLACE FUNCTION pg_temp.book_at(p_id text, p_ts timestamptz, p_label text)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.book_appointment_atomic(p_id, 'r_doc_1', 'x', 'x', 'Name', 30, 'M',
         p_ts, p_label, 'newVisit', NULL, NULL, NULL, 'patient_supabase', NULL);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.book_at(text, timestamptz, text) TO authenticated;
CREATE OR REPLACE FUNCTION pg_temp.move(p_id text, p_date date, p_slot text)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.reschedule_appointment_atomic(p_id, 'r_doc_1', p_date, p_slot, 'patient', NULL);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.move(text, date, text) TO authenticated;

SELECT tests.as_user('r_p1_uid');
SELECT tests.check('p1 books 15 Jan 10:00', (pg_temp.book_at('r_a1', '2031-01-15 10:00:00+05:30', '10:00 AM') ->> 'patient_id') = 'r_p1');

-- The chosen slot time is stored (it used to be 10:00 IST for every slot).
SELECT tests.check('reschedule stores the chosen slot time (IST)',
  (pg_temp.move('r_a1', DATE '2031-01-16', '11:30 AM') ->> 'date_time')::timestamptz = '2031-01-16 11:30:00+05:30'::timestamptz);
SELECT tests.check('row has the new time and label',
  EXISTS (SELECT 1 FROM public.appointments WHERE appointment_id = 'r_a1'
          AND date_time = '2031-01-16 11:30:00+05:30'::timestamptz AND slot_label = '11:30 AM'));
SELECT tests.check('PM slot converts to 24h',
  (pg_temp.move('r_a1', DATE '2031-01-16', '04:15 PM') ->> 'date_time')::timestamptz = '2031-01-16 16:15:00+05:30'::timestamptz);
SELECT tests.check('12 PM is noon',
  (pg_temp.move('r_a1', DATE '2031-01-16', '12:00 PM') ->> 'date_time')::timestamptz = '2031-01-16 12:00:00+05:30'::timestamptz);

SELECT tests.expect_error('slot must look like "10:30 AM"',
  $q$SELECT pg_temp.move('r_a1', DATE '2031-01-17', 'tomorrow')$q$, 'BAD_REQUEST');
SELECT tests.expect_error('cannot reschedule into the past',
  $q$SELECT pg_temp.move('r_a1', DATE '2020-01-01', '10:00 AM')$q$, 'BAD_REQUEST');

-- Capacity at the exact target time follows the booking rule (3 active).
SELECT tests.as_user('r_p2_uid');
SELECT tests.check('p2 books 20 Jan 09:00', (pg_temp.book_at('r_b2', '2031-01-20 09:00:00+05:30', '09:00 AM') ->> 'patient_id') = 'r_p2');
SELECT tests.as_user('r_p3_uid');
SELECT tests.check('p3 books 20 Jan 09:00', (pg_temp.book_at('r_b3', '2031-01-20 09:00:00+05:30', '09:00 AM') ->> 'patient_id') = 'r_p3');
SELECT tests.as_user('r_p4_uid');
SELECT tests.check('p4 books 20 Jan 09:00', (pg_temp.book_at('r_b4', '2031-01-20 09:00:00+05:30', '09:00 AM') ->> 'patient_id') = 'r_p4');
SELECT tests.as_user('r_p1_uid');
SELECT tests.expect_error('cannot move into a full slot',
  $q$SELECT pg_temp.move('r_a1', DATE '2031-01-20', '09:00 AM')$q$, 'SLOT_CAPACITY_REACHED');

-- A cancelled appointment stays cancelled.
SELECT tests.check('owner cancels',
  tests.affected($q$UPDATE public.appointments SET patient_status = 'cancelled' WHERE appointment_id = 'r_a1'$q$) = 1);
SELECT tests.expect_error('cancelled appointment cannot be re-opened by rescheduling',
  $q$SELECT pg_temp.move('r_a1', DATE '2031-01-18', '10:00 AM')$q$, 'INVALID_STATE');

-- Other patients still cannot move it.
SELECT tests.as_user('r_p2_uid');
SELECT tests.expect_error('other patient cannot reschedule',
  $q$SELECT pg_temp.move('r_a1', DATE '2031-01-18', '10:00 AM')$q$, 'FORBIDDEN');
