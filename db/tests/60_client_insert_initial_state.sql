-- 20261125000004: client INSERTs start in the initial state; server-owned columns are cleared.

SET LOCAL session_replication_role = replica;
SELECT tests.seed('public.users', '{"id":"t_pat_uid","firebase_uid":"t_pat_uid","role":"patient","profile_id":"t_pat_1"}');
SELECT tests.seed('public.users', '{"id":"t_doc_uid","firebase_uid":"t_doc_uid","role":"doctor","profile_id":"t_doc_1"}');
SELECT tests.seed('public.patients', '{"patient_id":"t_pat_1","owner_uid":"t_pat_uid","name":"P"}');
SELECT tests.seed('public.doctors', '{"doctor_id":"t_doc_1","owner_uid":"t_doc_uid","name":"Dr","verified":true,"deactivated":false}');
SELECT tests.seed('public.ambulances', '{"ambulance_id":"t_amb_1","ambulance_type":"bls","rating_count":0,"total_rating":0}');
SELECT tests.seed('public.labs', '{"lab_id":"t_lab_1","lab_name":"L"}');
SELECT tests.seed('public.medical_stores', '{"store_id":"t_store_1","store_name":"S"}');
SELECT tests.seed('public.prescriptions', '{"prescription_id":"t_rx_1","doctor_id":"t_doc_1","patient_id":"t_pat_1","patient_name":"P","patient_age":30}');
SET LOCAL session_replication_role = origin;

-- Patient fakes a completed trip with an arbitrary ambulance.
SELECT tests.as_user('t_pat_uid');
SELECT tests.seed('public.ambulance_broadcasts',
  '{"broadcast_id":"t_fake_trip","patient_id":"t_pat_1","status":"completed","accepted_driver_id":"t_amb_1","accepted_driver_phone":"9","rating":5}');
SELECT tests.as_owner();
SELECT tests.check('broadcast forced to pending with no driver/rating',
  (SELECT status = 'pending' AND accepted_driver_id IS NULL AND accepted_driver_phone IS NULL AND rating IS NULL
     FROM public.ambulance_broadcasts WHERE broadcast_id = 't_fake_trip'));
SELECT tests.as_service();
SELECT tests.expect_error('fake trip cannot be rated',
  $q$SELECT public.submit_ambulance_rating('t_fake_trip', 't_amb_1', 't_pat_1', 5, NULL)$q$, 'FAILED_PRECONDITION');

-- Patient creates a lab booking already completed with a report pointer.
SELECT tests.as_user('t_pat_uid');
SELECT tests.seed('public.lab_bookings',
  '{"booking_id":"t_bk_1","patient_id":"t_pat_1","lab_id":"t_lab_1","status":"completed","report_storage_key":"lab_reports/other/x.pdf","report_s3_key":"lab_reports/other/x.pdf"}');
SELECT tests.as_owner();
SELECT tests.check('lab booking forced to confirmed, report pointers cleared',
  (SELECT status = 'confirmed' AND report_storage_key IS NULL AND report_s3_key IS NULL
     FROM public.lab_bookings WHERE booking_id = 't_bk_1'));

-- Doctor-created orders / deliveries start at the beginning of their state machines.
SELECT tests.as_user('t_doc_uid');
SELECT tests.seed('public.lab_orders',
  '{"order_id":"t_lo_1","doctor_id":"t_doc_1","patient_id":"t_pat_1","lab_id":"t_lab_1","status":"completed","report_storage_key":"x"}');
SELECT tests.seed('public.pharmacy_deliveries',
  '{"delivery_id":"t_dl_1","doctor_id":"t_doc_1","patient_id":"t_pat_1","store_id":"t_store_1","prescription_id":"t_rx_1","status":"delivered"}');
SELECT tests.as_owner();
SELECT tests.check('lab order forced to ordered', (SELECT status = 'ordered' AND report_storage_key IS NULL FROM public.lab_orders WHERE order_id = 't_lo_1'));
SELECT tests.check('delivery forced to sent', (SELECT status = 'sent' FROM public.pharmacy_deliveries WHERE delivery_id = 't_dl_1'));

-- Trusted writers are unaffected.
SELECT tests.as_service();
SELECT tests.seed('public.ambulance_broadcasts',
  '{"broadcast_id":"t_srv_trip","patient_id":"t_pat_1","status":"completed","accepted_driver_id":"t_amb_1"}');
SELECT tests.as_owner();
SELECT tests.check('service_role insert keeps its status', (SELECT status = 'completed' FROM public.ambulance_broadcasts WHERE broadcast_id = 't_srv_trip'));
