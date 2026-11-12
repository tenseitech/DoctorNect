-- Staging probes: verified vs unverified provider RPCs (run after 000014 + 000017).
-- Expect 42501 for unverified lab/store/doctor mutators; success for verified fixtures.

-- \set lab_unverified_jwt ...
-- SELECT public.update_lab_booking_status('bk_staging_1', 'sampleCollected', NULL, NULL);
-- → FORBIDDEN: Verified lab required
