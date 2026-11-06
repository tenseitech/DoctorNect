-- PROPOSED (do not apply): align SECURITY DEFINER mutator RPCs with 000014-style verified flags
-- so unverified providers cannot bypass RLS via EXECUTE on these functions.
-- Depends on helpers in db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql:
--   private.is_verified_lab(), private.is_verified_medical_store()
-- Uses existing doctor check: private.is_verified_doctor() (db/migrations consolidated schema).

-- ---------------------------------------------------------------------------
-- Helper: verified ambulance driver (ambulances.verified, same pattern as lab/store)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_verified_ambulance_driver()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.ambulances
        WHERE ambulance_id = private.current_profile_id()
          AND verified IS TRUE
    );
$$;

REVOKE ALL ON FUNCTION private.is_verified_ambulance_driver() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_verified_ambulance_driver() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Table: mutator RPCs that change provider-owned or cross-entity state
-- | function | typical callers | checks is_verified_* today (deployed 20261026000001)? | proposed guard |
-- |----------|-----------------|--------------------------------------------------------|----------------|
-- | book_appointment_atomic | patient (+ family), admin | N/A (patient path) | no change |
-- | reschedule_appointment_atomic | patient, doctor, admin | no | require private.is_verified_doctor() when caller acts as doctor (doctor_id = profile); patient/family unchanged |
-- | create_prescription_atomic | doctor, admin | no | require private.is_verified_doctor() for non-admin doctor writes |
-- | update_lab_booking_status | lab, patient cancel, admin | lab branch: no | require private.is_verified_lab() for lab mutations; patient cancel unchanged |
-- | update_lab_order_status | lab, doctor cancel, admin | lab branch: no | require private.is_verified_lab() for lab mutations; doctor cancel unchanged |
-- | update_pharmacy_delivery_status | medical_store, patient cancel, admin | store branch: no | require private.is_verified_medical_store() for store mutations; patient cancel unchanged |
-- | accept_ambulance_request | ambulance driver, admin | no | require private.is_verified_ambulance_driver() OR admin |
-- | update_ambulance_location | ambulance driver, admin | no | same |
-- | complete_ambulance_trip | ambulance driver, admin | no | same |
-- | cancel_ambulance_broadcast | patient, admin | N/A | no change (patient) |
-- | get_ambulance_trip_location | patient, driver, admin | read-only | no change |
-- | get_ambulance_trip_contact | patient, driver, admin | read-only | no change |
-- Onboarding / profile RPCs (relogin upsert, claim_ambulance_driver, etc.) are out of scope here.
-- ---------------------------------------------------------------------------

-- NOTE: Full CREATE OR REPLACE bodies belong in a follow-on migration that patches
-- db/migrations/20261026000001_rpc_null_safe_authz.sql in lockstep with deploy.
-- Below are the minimal guard snippets to insert after role resolution (v_is_lab / v_is_doctor / v_driver_id):

-- reschedule_appointment_atomic: after v_is_admin resolved, before appointment lock —
-- IF p_rescheduled_by ILIKE 'doctor%' AND NOT v_is_admin THEN
--   IF NOT COALESCE(private.is_verified_doctor(), FALSE) THEN
--     RAISE EXCEPTION 'FORBIDDEN: Verified doctor required' USING ERRCODE = '42501';
--   END IF;
-- END IF;

-- create_prescription_atomic: after v_doctor_id resolved, before INSERT —
-- IF NOT v_is_admin AND NOT COALESCE(private.is_verified_doctor(), FALSE) THEN
--   RAISE EXCEPTION 'FORBIDDEN: Verified doctor required' USING ERRCODE = '42501';
-- END IF;

-- update_lab_booking_status: in ELSIF v_is_lab branch, before state machine —
-- IF NOT COALESCE(private.is_verified_lab(), FALSE) THEN
--   RAISE EXCEPTION 'FORBIDDEN: Verified lab required' USING ERRCODE = '42501';
-- END IF;

-- update_lab_order_status: in ELSIF v_is_lab branch —
-- IF NOT COALESCE(private.is_verified_lab(), FALSE) THEN
--   RAISE EXCEPTION 'FORBIDDEN: Verified lab required' USING ERRCODE = '42501';
-- END IF;

-- update_pharmacy_delivery_status: in IF v_is_store branch —
-- IF NOT COALESCE(private.is_verified_medical_store(), FALSE) THEN
--   RAISE EXCEPTION 'FORBIDDEN: Verified medical store required' USING ERRCODE = '42501';
-- END IF;

-- accept_ambulance_request / update_ambulance_location / complete_ambulance_trip: after v_driver_id resolved —
-- IF NOT v_is_admin AND NOT COALESCE(private.is_verified_ambulance_driver(), FALSE) THEN
--   RAISE EXCEPTION 'FORBIDDEN: Verified ambulance driver required' USING ERRCODE = '42501';
-- END IF;
