-- 20261124000002: prescriptions writes require a care relationship; no client deletes.

SET LOCAL session_replication_role = replica;
SELECT tests.seed('public.users', '{"id":"t_doc_uid","firebase_uid":"t_doc_uid","role":"doctor","profile_id":"t_doc_1"}');
SELECT tests.seed('public.users', '{"id":"t_unv_uid","firebase_uid":"t_unv_uid","role":"doctor","profile_id":"t_doc_unv"}');
SELECT tests.seed('public.users', '{"id":"t_pat_uid","firebase_uid":"t_pat_uid","role":"patient","profile_id":"t_pat_1"}');
SELECT tests.seed('public.doctors', '{"doctor_id":"t_doc_1","owner_uid":"t_doc_uid","name":"Dr A","verified":true,"deactivated":false}');
SELECT tests.seed('public.doctors', '{"doctor_id":"t_doc_unv","owner_uid":"t_unv_uid","name":"Dr U","verified":false,"deactivated":false}');
SELECT tests.seed('public.patients', '{"patient_id":"t_pat_1","owner_uid":"t_pat_uid","name":"P One"}');
SELECT tests.seed('public.patients', '{"patient_id":"t_pat_2","name":"P Two"}');
SELECT tests.seed('public.patient_doctor_links', '{"patient_id":"t_pat_1","doctor_id":"t_doc_1","source":"manual"}');
SELECT tests.seed('public.patient_doctor_links', '{"patient_id":"t_pat_1","doctor_id":"t_doc_unv","source":"manual"}');
SET LOCAL session_replication_role = origin;

SELECT tests.as_user('t_doc_uid');

SELECT tests.expect_error('verified doctor WITHOUT relationship cannot insert',
  $q$INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, patient_name, patient_age) VALUES ('t_rx_bad', 't_doc_1', 't_pat_2', 'P', 30)$q$);

SELECT tests.check('verified doctor WITH relationship can insert',
  tests.affected($q$INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, patient_name, patient_age) VALUES ('t_rx_ok', 't_doc_1', 't_pat_1', 'P', 30)$q$) = 1);

SELECT tests.expect_error('cannot insert under another doctor id',
  $q$INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, patient_name, patient_age) VALUES ('t_rx_spoof', 't_doc_unv', 't_pat_1', 'P', 30)$q$);

SELECT tests.expect_error('cannot re-target own prescription to an unrelated patient',
  $q$UPDATE public.prescriptions SET patient_id = 't_pat_2' WHERE prescription_id = 't_rx_ok'$q$);

SELECT tests.expect_error('doctor cannot DELETE prescriptions',
  $q$DELETE FROM public.prescriptions WHERE prescription_id = 't_rx_ok'$q$);

-- create_prescription_atomic keeps working for a related patient and refuses unrelated ones.
SELECT tests.check('create_prescription_atomic with relationship',
  (public.create_prescription_atomic('{"prescription_id":"t_rx_rpc","patient_id":"t_pat_1","patient_name":"P","patient_age":30,"medicines":[],"investigations":[],"referrals":[]}'::jsonb)) IS NOT NULL);
SELECT tests.expect_error('create_prescription_atomic without relationship',
  $q$SELECT public.create_prescription_atomic('{"prescription_id":"t_rx_rpc2","patient_id":"t_pat_2"}'::jsonb)$q$);

-- Unverified doctor with a link still cannot write.
SELECT tests.as_user('t_unv_uid');
SELECT tests.expect_error('unverified doctor cannot insert',
  $q$INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, patient_name, patient_age) VALUES ('t_rx_unv', 't_doc_unv', 't_pat_1', 'P', 30)$q$);
SELECT tests.expect_error('unverified doctor cannot use create_prescription_atomic',
  $q$SELECT public.create_prescription_atomic('{"prescription_id":"t_rx_unv2","patient_id":"t_pat_1"}'::jsonb)$q$);

-- Patient cannot write prescriptions at all.
SELECT tests.as_user('t_pat_uid');
SELECT tests.expect_error('patient cannot insert a prescription',
  $q$INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, patient_name, patient_age) VALUES ('t_rx_pat', 't_doc_1', 't_pat_1', 'P', 30)$q$);

SELECT tests.as_owner();
SELECT tests.check('exactly the two legitimate prescriptions exist',
  (SELECT count(*) FROM public.prescriptions WHERE prescription_id LIKE 't_rx_%') = 2);
