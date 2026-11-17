'use strict';

/** Tables touched by harness fixture seed (INSERT only). Used for audit logging. */
const SEED_TABLE_PATTERN =
  /(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+((?:public|private)\.[a-z_][a-z0-9_]*)/gi;

function extractHarnessSeedTables(sql) {
  const found = new Set();
  let m;
  const re = new RegExp(SEED_TABLE_PATTERN.source, 'gi');
  while ((m = re.exec(sql)) !== null) {
    found.add(m[1].toLowerCase());
  }
  return [...found].sort();
}

/**
 * @param {Array<{ label: string, sql: string }>} steps
 */
function listHarnessSeedTables(steps) {
  const all = new Set();
  for (const step of steps) {
    for (const t of extractHarnessSeedTables(step.sql)) {
      all.add(t);
    }
  }
  return [...all].sort();
}

/**
 * Logs tables referenced by seed SQL; throws if steps list is empty.
 * Call only from inside withHarnessSeedDml.
 */
function assertHarnessSeedSteps(steps) {
  if (!steps.length) {
    throw new Error('[harness-seed] no seed steps defined');
  }
  const tables = listHarnessSeedTables(steps);
  return { tables, stepCount: steps.length };
}

function buildHarnessSeedSteps(v) {
  return [
    {
      label: 'users',
      sql: `
      INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES
        ('${v.pA}', '${v.pA}', 'patient', '${v.pA}', 'Patient A', 'pa@test.local', '+919999900001', true),
        ('${v.pB}', '${v.pB}', 'patient', '${v.pB}', 'Patient B', 'pb@test.local', '+919999900002', true),
        ('${v.docA}', '${v.docA}', 'doctor', '${v.docA}', 'Dr A', 'da@test.local', '+919999900003', true),
        ('${v.docB}', '${v.docB}', 'doctor', '${v.docB}', 'Dr B', 'db@test.local', '+919999900004', true),
        ('${v.storeA}', '${v.storeA}', 'medicalStore', '${v.storeA}', 'Store A', 'sa@test.local', '+919999900005', true),
        ('${v.storeB}', '${v.storeB}', 'medicalStore', '${v.storeB}', 'Store B', 'sb@test.local', '+919999900006', true),
        ('${v.labA}', '${v.labA}', 'lab', '${v.labA}', 'Lab A', 'la@test.local', '+919999900007', true),
        ('${v.labB}', '${v.labB}', 'lab', '${v.labB}', 'Lab B', 'lb@test.local', '+919999900008', true),
        ('${v.ambA}', '${v.ambA}', 'ambulance', '${v.ambA}', 'Amb A', 'aa@test.local', '+919999900009', true),
        ('${v.ambB}', '${v.ambB}', 'ambulance', '${v.ambB}', 'Amb B', 'ab@test.local', '+919999900010', true),
        ('test_usr_doc_unverified', 'test_usr_doc_unverified', 'doctor', 'test_usr_doc_unverified', 'Dr. Unverified', 'unverified@test.local', '+919999900099', false),
        ('super_admin_test_uid', 'super_admin_test_uid', 'super_admin', 'super_admin_test_uid', 'Harness Super Admin', 'super_admin_harness@test.local', '+919999900011', true),
        ('test_usr_lab_unverified', 'test_usr_lab_unverified', 'lab', 'test_usr_lab_unverified', 'Lab Unverified', 'unverified_lab@test.local', '+919999900098', false),
        ('test_usr_store_unverified', 'test_usr_store_unverified', 'medicalStore', 'test_usr_store_unverified', 'Store Unverified', 'unverified_store@test.local', '+919999900097', false),
        ('test_usr_amb_unverified', 'test_usr_amb_unverified', 'ambulance', 'test_usr_amb_unverified', 'Amb Unverified', 'unverified_amb@test.local', '+919999900096', false),
        ('test_usr_amb_unclaimed', 'test_usr_amb_unclaimed', 'ambulance', 'test_amb_unclaimed', 'Driver Unclaimed', 'unclaimed_amb@test.local', '+919999900095', true),
        ('test_usr_doc_suspended', 'test_usr_doc_suspended', 'doctor', 'test_usr_doc_suspended', 'Dr. Suspended', 'suspended@test.local', '+919999900088', true)
      ON CONFLICT (id) DO NOTHING;
    `,
    },
    {
      label: 'admin_users',
      sql: `
      INSERT INTO private.admin_users (user_id)
      VALUES ('super_admin_test_uid')
      ON CONFLICT (user_id) DO NOTHING;
    `,
    },
    {
      label: 'domain_profiles_and_reviews',
      sql: `
      INSERT INTO public.patients (patient_id, owner_uid, name, mobile, share_records_with_doctors) VALUES
        ('${v.pA}', '${v.pA}', 'Patient A', '+919999900001', true),
        ('${v.pB}', '${v.pB}', 'Patient B', '+919999900002', false),
        ('test_fam_a1', '${v.pA}', 'Child A', '+919999900001', true);
      INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated) VALUES
        ('test_orphan_doc', NULL, 'Orphan Dr', 'orphan@test.local', '+919999900998', 'General', 'MBBS', true, false),
        ('${v.docA}', '${v.docA}', 'Dr. A', 'da@test.local', '+919999900003', 'General', 'MBBS', true, false),
        ('${v.docB}', '${v.docB}', 'Dr. B', 'db@test.local', '+919999900004', 'Cardiology', 'MD', true, false),
        ('test_usr_doc_unverified', 'test_usr_doc_unverified', 'Dr. Unverified', 'unverified@test.local', '+919999900099', 'General', 'MBBS', false, false),
        ('test_usr_doc_suspended', 'test_usr_doc_suspended', 'Dr. Suspended', 'suspended@test.local', '+919999900088', 'General', 'MBBS', true, true);
      INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified) VALUES
        ('${v.storeA}', '${v.storeA}', 'Store A', 'Owner A', 'DL-001', '+919999900005', 'sa@test.local', true),
        ('${v.storeB}', '${v.storeB}', 'Store B', 'Owner B', 'DL-002', '+919999900006', 'sb@test.local', true),
        ('test_usr_store_unverified', 'test_usr_store_unverified', 'Unverified Store', 'Owner U', 'DL-999', '+919999900097', 'unverified_store@test.local', false);
      INSERT INTO public.labs (lab_id, owner_uid, lab_name, license_number, phone, email, verified) VALUES
        ('${v.labA}', '${v.labA}', 'Lab A', 'LIC-001', '+919999900007', 'la@test.local', true),
        ('${v.labB}', '${v.labB}', 'Lab B', 'LIC-002', '+919999900008', 'lb@test.local', true),
        ('test_usr_lab_unverified', 'test_usr_lab_unverified', 'Unverified Lab', 'LIC-999', '+919999900098', 'unverified_lab@test.local', false);
      INSERT INTO public.ambulances (ambulance_id, auth_uid, service_name, driver_name, phone, vehicle_number, ambulance_type, city, verified) VALUES
        ('${v.ambA}', '${v.ambA}', 'Amb Service A', 'Driver A', '+919999900009', 'DL-01-A-1000', 'bls', 'Delhi', true),
        ('${v.ambB}', '${v.ambB}', 'Amb Service B', 'Driver B', '+919999900010', 'DL-01-B-2000', 'icu', 'Delhi', true),
        ('test_usr_amb_unverified', 'test_usr_amb_unverified', 'Unverified Amb', 'Driver U', '+919999900096', 'DL-01-U-9999', 'bls', 'Delhi', false),
        ('test_amb_unclaimed', NULL, 'Unclaimed Amb', 'Driver Unclaimed', '+919999900095', 'DL-01-U-0000', 'bls', 'Delhi', false),
        ('test_amb_unclaimed_flow', NULL, 'Flow Amb', 'Driver Flow', '+919999900055', 'DL-01-U-5555', 'bls', 'Delhi', false);
      INSERT INTO public.reviews (review_id, patient_id, doctor_id, patient_name, rating, comment) VALUES
        ('test_rev_harness_docA', '${v.pA}', '${v.docA}', 'Patient A', 5, 'Visible for anon review_public'),
        ('test_rev_harness_suspended', '${v.pA}', 'test_usr_doc_suspended', 'Patient A', 3, 'Hidden suspended doctor review'),
        ('test_rev_harness_unverified', '${v.pA}', 'test_usr_doc_unverified', 'Patient A', 2, 'Hidden unverified doctor review')
      ON CONFLICT (review_id) DO NOTHING;
    `,
    },
    {
      label: 'appointments_ambulance_pharmacy_lab',
      sql: `
      INSERT INTO public.appointments (appointment_id, doctor_id, patient_id, doctor_name, specialization, patient_name, patient_age, patient_gender, date_time, slot_label, visit_type, patient_status, doctor_status) VALUES
        ('${v.apptId}', '${v.docA}', '${v.pA}', 'Dr. A', 'General', 'Patient A', 30, 'Male', now(), '10:00 AM', 'newVisit', 'confirmed', 'confirmed'),
        ('appt_happy_fam', '${v.docA}', 'test_fam_a1', 'Dr. A', 'General', 'Child A', 8, 'Female', now() + interval '2 days', '11:30 AM', 'newVisit', 'confirmed', 'confirmed'),
        ('appt_completed_docA', '${v.docA}', '${v.pA}', 'Dr. A', 'General', 'Patient A', 30, 'Male', now() - interval '1 day', '10:00 AM', 'newVisit', 'completed', 'completed'),
        ('appt_completed_fam', '${v.docA}', 'test_fam_a1', 'Dr. A', 'General', 'Child A', 8, 'Female', now() - interval '1 day', '11:00 AM', 'newVisit', 'completed', 'completed')
      ON CONFLICT (appointment_id) DO NOTHING;
      INSERT INTO public.health_records (record_id, patient_id, title, type, date, source, file_name, shared_with_doctors) VALUES
        ('${v.hrId}', '${v.pA}', 'CBC Report', 'labReport', CURRENT_DATE, 'selfUploaded', 'cbc.pdf', true);
      INSERT INTO public.ambulance_broadcasts (broadcast_id, patient_id, patient_name, contact_phone, pickup_location, drop_location, status, accepted_driver_id, accepted_driver_phone) VALUES
        ('${v.bcId}', '${v.pA}', 'Patient A', '+919999900001', 'Connaught Place', 'AIIMS', 'accepted', '${v.ambA}', '+919999900009'),
        ('${v.bcPendingId}', '${v.pA}', 'Patient A', '+919999900001', 'Karol Bagh', 'Safdarjung', 'pending', NULL, NULL),
        ('${v.bcCancelledId}', '${v.pA}', 'Patient A', '+919999900001', 'Rohini', 'Fortis', 'cancelled', '${v.ambA}', '+919999900009');
      INSERT INTO public.ambulance_requests (request_id, broadcast_id, driver_id, patient_id, patient_name, pickup_location, drop_location, contact_phone, status) VALUES
        ('${v.reqId}', '${v.bcId}', '${v.ambA}', '${v.pA}', 'Patient A', 'Connaught Place', 'AIIMS', '+919999900001', 'accepted'),
        ('${v.reqPendingId}', '${v.bcPendingId}', '${v.ambA}', '${v.pA}', 'Patient A', 'Karol Bagh', 'Safdarjung', '+919999900001', 'pending');
      INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, appointment_id, patient_name, patient_age) VALUES
        ('test_rx_alpha', '${v.docA}', '${v.pA}', '${v.apptId}', 'Patient A', 30);
      INSERT INTO public.pharmacy_deliveries (delivery_id, prescription_id, doctor_id, store_id, patient_id, doctor_name, store_name, patient_name, status) VALUES
        ('${v.delId}', 'test_rx_alpha', '${v.docA}', '${v.storeA}', '${v.pA}', 'Dr. A', 'Store A', 'Patient A', 'sent');
      INSERT INTO public.pharmacy_delivery_medicines (delivery_id, medicine_entry_id, availability, substitute_name) VALUES
        ('${v.delId}', 'med_1', 'pending', NULL)
      ON CONFLICT DO NOTHING;
      INSERT INTO public.ambulance_trip_contacts (broadcast_id, patient_phone, driver_phone) VALUES
        ('${v.bcId}', '+919999900001', '+919999900009')
      ON CONFLICT DO NOTHING;
      INSERT INTO public.family_members (member_id, patient_id, name, relation, age, gender) VALUES
        ('test_fam_a1', '${v.pA}', 'Child A', 'child', 8, 'Female')
      ON CONFLICT DO NOTHING;
      INSERT INTO public.lab_bookings (booking_id, lab_id, patient_id, patient_name, patient_age, test_id, test_name, test_names, collection_type, date_time, slot_label, status) VALUES
        ('${v.labBkId}', '${v.labA}', '${v.pA}', 'Patient A', 30, 't1', 'Blood Test', ARRAY['Blood Test'], 'labVisit', CURRENT_TIMESTAMP, '10:00 AM', 'confirmed');
      INSERT INTO public.lab_orders (order_id, lab_id, doctor_id, patient_id, doctor_name, patient_name, patient_age, test_ids, test_names, status) VALUES
        ('${v.labOrdId}', '${v.labA}', '${v.docA}', '${v.pA}', 'Dr. A', 'Patient A', 30, ARRAY['t1'], ARRAY['Lipid Profile'], 'ordered');
    `,
    },
  ];
}

module.exports = {
  buildHarnessSeedSteps,
  listHarnessSeedTables,
  assertHarnessSeedSteps,
  extractHarnessSeedTables,
};