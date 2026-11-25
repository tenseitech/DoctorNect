-- 20261124000003: submit_ambulance_rating records one rating per completed trip and
-- updates aggregates exactly once.

SET LOCAL session_replication_role = replica;
SELECT tests.seed('public.ambulances', '{"ambulance_id":"t_amb_1","ambulance_type":"bls","rating_count":2,"total_rating":9}');
SELECT tests.seed('public.ambulance_broadcasts', '{"broadcast_id":"t_trip_done","patient_id":"t_pat_1","accepted_driver_id":"t_amb_1","status":"completed"}');
SELECT tests.seed('public.ambulance_broadcasts', '{"broadcast_id":"t_trip_open","patient_id":"t_pat_1","accepted_driver_id":"t_amb_1","status":"accepted"}');
SELECT tests.seed('public.ambulance_broadcasts', '{"broadcast_id":"t_trip_skip","patient_id":"t_pat_1","accepted_driver_id":"t_amb_1","status":"completed","rating":-1}');
SET LOCAL session_replication_role = origin;

-- Not callable by clients.
SELECT tests.as_user('t_pat_uid');
SELECT tests.expect_error('authenticated cannot EXECUTE',
  $q$SELECT public.submit_ambulance_rating('t_trip_done', 't_amb_1', 't_pat_1', 5, NULL)$q$);
SET LOCAL ROLE anon;
SELECT tests.expect_error('anon cannot EXECUTE',
  $q$SELECT public.submit_ambulance_rating('t_trip_done', 't_amb_1', 't_pat_1', 5, NULL)$q$);

SELECT tests.as_service();
SELECT tests.check('first rating succeeds',
  (public.submit_ambulance_rating('t_trip_done', 't_amb_1', 't_pat_1', 4, '  quick  ') ->> 'ok')::boolean);
SELECT tests.expect_error('second rating is rejected (ALREADY_EXISTS)',
  $q$SELECT public.submit_ambulance_rating('t_trip_done', 't_amb_1', 't_pat_1', 1, NULL)$q$, 'ALREADY_EXISTS');
SELECT tests.expect_error('other patient FORBIDDEN',
  $q$SELECT public.submit_ambulance_rating('t_trip_done', 't_amb_1', 't_pat_2', 5, NULL)$q$, 'FORBIDDEN');
SELECT tests.expect_error('wrong ambulance INVALID_ARGUMENT',
  $q$SELECT public.submit_ambulance_rating('t_trip_done', 't_amb_x', 't_pat_1', 5, NULL)$q$, 'INVALID_ARGUMENT');
SELECT tests.expect_error('open trip FAILED_PRECONDITION',
  $q$SELECT public.submit_ambulance_rating('t_trip_open', 't_amb_1', 't_pat_1', 5, NULL)$q$, 'FAILED_PRECONDITION');
SELECT tests.expect_error('skipped trip FAILED_PRECONDITION',
  $q$SELECT public.submit_ambulance_rating('t_trip_skip', 't_amb_1', 't_pat_1', 5, NULL)$q$, 'FAILED_PRECONDITION');
SELECT tests.expect_error('unknown trip NOT_FOUND',
  $q$SELECT public.submit_ambulance_rating('t_trip_none', 't_amb_1', 't_pat_1', 5, NULL)$q$, 'NOT_FOUND');
SELECT tests.expect_error('stars out of range rejected',
  $q$SELECT public.submit_ambulance_rating('t_trip_open', 't_amb_1', 't_pat_1', 6, NULL)$q$, 'BAD_REQUEST');

SELECT tests.as_owner();
SELECT tests.check('trip rating stored once', (SELECT rating = 4 AND review = 'quick' FROM public.ambulance_broadcasts WHERE broadcast_id = 't_trip_done'));
SELECT tests.check('aggregates incremented exactly once',
  (SELECT rating_count = 3 AND total_rating = 13 FROM public.ambulances WHERE ambulance_id = 't_amb_1'));
