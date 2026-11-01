'use strict';

const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');
const { bootstrapMutatingScript } = require('../lib/mutating_script_bootstrap');

async function testDoctorUpdate() {
  bootstrapMutatingScript('scripts/db/test_doctor_relogin_upsert.js');
  const c = new Client({ connectionString: getEnv('STAGING_SUPABASE_DB_URL') });
  await c.connect();

  await c.query('BEGIN');
  try {
    // 1. Authenticated registration as doctor
    await c.query("SET LOCAL ROLE authenticated;");
    await c.query("SELECT set_config('request.jwt.claim.sub', 'usr_doc_test', true);");
    await c.query("SELECT set_config('request.jwt.claim.role', 'authenticated', true);");
    await c.query("SELECT set_config('request.jwt.claims', '{\"sub\":\"usr_doc_test\",\"role\":\"authenticated\",\"user_role\":\"doctor\"}', true);");

    await c.query(`
      INSERT INTO public.users (id, firebase_uid, mobile, role, profile_id, display_name, email)
      VALUES ('usr_doc_test', 'usr_doc_test', '+919999988888', 'doctor', 'doc_test_1', 'Dr Test', 'drtest@example.com');
      INSERT INTO public.doctors (doctor_id, owner_uid, name, mobile, email, specialization, qualification, verified)
      VALUES ('doc_test_1', 'usr_doc_test', 'Dr Test', '+919999988888', 'drtest@example.com', 'Cardiologist', 'MBBS, MD', false);
    `);

    // 2. Admin approves doctor (service_role)
    await c.query("SET LOCAL ROLE service_role;");
    await c.query("SELECT set_config('request.jwt.claim.sub', 'admin_service', true);");
    await c.query("SELECT set_config('request.jwt.claim.role', 'service_role', true);");
    await c.query("SELECT set_config('request.jwt.claims', '{\"sub\":\"admin_service\",\"role\":\"service_role\"}', true);");
    await c.query("UPDATE public.doctors SET verified = true WHERE doctor_id = 'doc_test_1';");

    // Install improved trigger function within this transaction
    await c.query("RESET ROLE;");
    await c.query(`
      CREATE OR REPLACE FUNCTION private.trg_domain_profile_guard_update()
       RETURNS trigger
       LANGUAGE plpgsql
       SECURITY DEFINER
       SET search_path TO ''
      AS $function$
      DECLARE
          v_old JSONB := to_jsonb(OLD);
          v_new JSONB;
          v_caller_sub TEXT;
          v_owner_val TEXT;
          v_allowed_cols TEXT[];
          v_kyc_cols TEXT[];
          v_key TEXT;
          v_is_verified BOOLEAN;
      BEGIN
          -- Privileged session bypass: service_role, super_admin, or direct backend/migration session
          IF (auth.jwt() ->> 'role') = 'service_role'
             OR COALESCE(private.is_super_admin(), FALSE)
             OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
                 AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
              RETURN NEW;
          END IF;

          -- Trusted RPC bypass for provider lifecycle management (deactivate/reactivate)
          IF current_setting('app.allow_provider_lifecycle_change', true) = 'true' THEN
              RETURN NEW;
          END IF;

          -- Internal trigger aggregate recalculation bypass (pg_trigger_depth() > 1)
          IF pg_trigger_depth() > 1 THEN
              FOR v_key IN SELECT jsonb_object_keys(to_jsonb(NEW)) LOOP
                  IF (to_jsonb(NEW) ->> v_key) IS DISTINCT FROM (v_old ->> v_key) THEN
                      IF v_key IN ('rating', 'review_count', 'total_reviews', 'total_rating', 'rating_count', 'total_ratings', 'updated_at') THEN
                          CONTINUE;
                      ELSE
                          RAISE EXCEPTION 'FORBIDDEN: Internal trigger cannot modify column "%"', v_key
                              USING ERRCODE = '42501';
                      END IF;
                  END IF;
              END LOOP;
              RETURN NEW;
          END IF;

          -- Provider re-login upsert invariant:
          -- If provider is already verified, preserve verified=true on client updates sending verified=false
          IF TG_TABLE_NAME IN ('doctors', 'labs', 'medical_stores', 'ambulances') THEN
              IF (OLD.verified IS TRUE) AND (NEW.verified IS FALSE OR NEW.verified IS NULL) THEN
                  NEW.verified := OLD.verified;
              END IF;
          END IF;

          v_new := to_jsonb(NEW);

          v_caller_sub := NULLIF(COALESCE(
              auth.jwt() ->> 'sub',
              auth.jwt() ->> 'uid',
              current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
          ), '');

          -- Determine owner UID of the existing row
          IF TG_TABLE_NAME = 'ambulances' THEN
              v_owner_val := v_old ->> 'auth_uid';
          ELSE
              v_owner_val := v_old ->> 'owner_uid';
          END IF;

          -- Strict ownership enforcement: Caller must be the owner of the profile
          IF v_owner_val IS DISTINCT FROM v_caller_sub THEN
              RAISE EXCEPTION 'FORBIDDEN: Caller is not the owner of this domain profile'
                  USING ERRCODE = '42501';
          END IF;

          -- Prevent modifying ownership columns
          IF TG_TABLE_NAME = 'ambulances' THEN
              IF (v_new ->> 'auth_uid') IS DISTINCT FROM (v_old ->> 'auth_uid') THEN
                  RAISE EXCEPTION 'FORBIDDEN: Modifying column "auth_uid" on table "ambulances" is not permitted (not client-editable)'
                      USING ERRCODE = '42501';
              END IF;
          ELSE
              IF (v_new ->> 'owner_uid') IS DISTINCT FROM (v_old ->> 'owner_uid') THEN
                  RAISE EXCEPTION 'FORBIDDEN: Modifying column "owner_uid" on table "%" is not permitted (not client-editable)',
                      TG_TABLE_NAME
                      USING ERRCODE = '42501';
              END IF;
          END IF;

          -- KYC Field Immutability Check:
          v_is_verified := COALESCE((v_old ->> 'verified')::boolean, (v_old ->> 'is_verified')::boolean, FALSE);

          IF TG_TABLE_NAME = 'doctors' THEN
              v_kyc_cols := ARRAY['council_number', 'state_council', 'certifications'];
              v_allowed_cols := ARRAY[
                  'name', 'email', 'mobile', 'specialization', 'super_specialization',
                  'qualification', 'experience_years', 'consultation_fee', 'clinic_name',
                  'primary_facility_id', 'area', 'city', 'state', 'country', 'pincode',
                  'address_line1', 'address_line2', 'state_council', 'council_number',
                  'certifications', 'past_workplaces', 'memberships', 'awards',
                  'publications', 'about', 'languages', 'photo_url', 'maps_link',
                  'landmark', 'profile_completed', 'fcm_token', 'fcm_token_updated_at',
                  'photo_key', 'photo_storage', 'photo_s3_key', 'photo_s3_bucket',
                  'photo_storage_provider', 'photo_updated_at'
              ];
          ELSIF TG_TABLE_NAME = 'labs' THEN
              v_kyc_cols := ARRAY['license_number', 'gst_number'];
              v_allowed_cols := ARRAY[
                  'lab_name', 'license_number', 'phone', 'email', 'gst_number',
                  'area', 'city', 'state', 'country', 'pincode', 'address_line1',
                  'address_line2', 'profile_completed'
              ];
          ELSIF TG_TABLE_NAME = 'medical_stores' THEN
              v_kyc_cols := ARRAY['drug_license_number', 'gst_number'];
              v_allowed_cols := ARRAY[
                  'store_name', 'owner_name', 'drug_license_number', 'phone', 'email',
                  'gst_number', 'address_line1', 'address_line2', 'city', 'state',
                  'country', 'pincode', 'profile_completed'
              ];
          ELSIF TG_TABLE_NAME = 'ambulances' THEN
              v_kyc_cols := ARRAY['vehicle_number', 'license_number', 'insurance_number'];
              v_allowed_cols := ARRAY[
                  'service_name', 'owner_name', 'driver_name', 'phone', 'vehicle_number',
                  'ambulance_type', 'username', 'city', 'base_address', 'license_number',
                  'insurance_number', 'has_oxygen', 'has_ventilator', 'has_stretcher',
                  'is_24x7', 'rate_per_km', 'is_available', 'profile_completed',
                  'address_line1', 'address_line2', 'state', 'country', 'pincode',
                  'service_areas'
              ];
          ELSIF TG_TABLE_NAME = 'patients' THEN
              v_kyc_cols := ARRAY[]::TEXT[];
              v_allowed_cols := ARRAY[
                  'name', 'email', 'mobile', 'age', 'gender', 'blood_group', 'height',
                  'weight', 'address', 'photo_url', 'share_records_with_doctors',
                  'primary_doctor_id', 'invited_doctor_id', 'care_team_doctor_ids',
                  'profile_completed', 'fcm_token', 'fcm_token_updated_at', 'city',
                  'state', 'pincode', 'country', 'conditions', 'allergies', 'metadata',
                  'photo_key', 'photo_storage', 'photo_s3_key', 'photo_s3_bucket',
                  'photo_storage_provider', 'photo_updated_at'
              ];
          ELSE
              RETURN NEW;
          END IF;

          -- Iterate over updated columns
          FOR v_key IN SELECT jsonb_object_keys(v_new) LOOP
              IF (v_new ->> v_key) IS NOT DISTINCT FROM (v_old ->> v_key) THEN
                  CONTINUE;
              END IF;

              IF v_key = 'updated_at' THEN
                  CONTINUE;
              END IF;

              IF v_is_verified AND (v_key = ANY(v_kyc_cols)) THEN
                  RAISE EXCEPTION 'FORBIDDEN: KYC column "%" on table "%" is immutable once verified',
                      v_key, TG_TABLE_NAME
                      USING ERRCODE = '42501';
              END IF;

              IF NOT (v_key = ANY(v_allowed_cols)) THEN
                  RAISE EXCEPTION 'FORBIDDEN: Modifying column "%" on table "%" is not permitted (not client-editable)',
                      v_key, TG_TABLE_NAME
                      USING ERRCODE = '42501';
              END IF;
          END LOOP;

          RETURN NEW;
      END;
      $function$;
    `);

    // 3. Switch back to doctor
    await c.query("SET LOCAL ROLE authenticated;");
    await c.query("SELECT set_config('request.jwt.claim.sub', 'usr_doc_test', true);");
    await c.query("SELECT set_config('request.jwt.claim.role', 'authenticated', true);");
    await c.query("SELECT set_config('request.jwt.claims', '{\"sub\":\"usr_doc_test\",\"role\":\"authenticated\",\"user_role\":\"doctor\"}', true);");

    // 4. Doctor re-logs in and client does upsert payload with verified: false
    const res = await c.query("UPDATE public.doctors SET verified = false, name = 'Dr Test Renamed' WHERE doctor_id = 'doc_test_1';");
    const checkRes = await c.query("SELECT verified, name FROM public.doctors WHERE doctor_id = 'doc_test_1';");
    console.log('RESULT: UPDATE_SUCCESS, rowCount =', res.rowCount, 'verified =', checkRes.rows[0].verified, 'name =', checkRes.rows[0].name);

    // 5. Admin un-verifies doctor, then unverified doctor tries to set verified = true
    await c.query("SET LOCAL ROLE service_role;");
    await c.query("SELECT set_config('request.jwt.claim.sub', 'admin_service', true);");
    await c.query("SELECT set_config('request.jwt.claim.role', 'service_role', true);");
    await c.query("SELECT set_config('request.jwt.claims', '{\"sub\":\"admin_service\",\"role\":\"service_role\"}', true);");
    await c.query("UPDATE public.doctors SET verified = false WHERE doctor_id = 'doc_test_1';");

    await c.query("SET LOCAL ROLE authenticated;");
    await c.query("SELECT set_config('request.jwt.claim.sub', 'usr_doc_test', true);");
    await c.query("SELECT set_config('request.jwt.claim.role', 'authenticated', true);");
    await c.query("SELECT set_config('request.jwt.claims', '{\"sub\":\"usr_doc_test\",\"role\":\"authenticated\",\"user_role\":\"doctor\"}', true);");
    try {
      await c.query("UPDATE public.doctors SET verified = true WHERE doctor_id = 'doc_test_1';");
      console.log('RESULT: UNVERIFIED_SET_TRUE_SHOULD_HAVE_FAILED');
    } catch (e) {
      console.log('RESULT: UNVERIFIED_SET_TRUE_BLOCKED code=' + e.code + ' msg=' + e.message);
    }
  } catch (err) {
    console.log(`RESULT: ERROR code=${err.code} msg=${err.message}`);
  } finally {
    await c.query('ROLLBACK');
    await c.end();
  }
}

testDoctorUpdate().catch(console.error);
