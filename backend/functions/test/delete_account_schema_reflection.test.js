'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Client } = require('../../node_modules/pg');

const DOCKER_PG_URL = process.env.LOCAL_DOCKER_PG_URL || 'postgres://postgres:postgres@127.0.0.1:54322/postgres';

async function connectOrSkip(t, testName) {
  const pgClient = new Client({ connectionString: DOCKER_PG_URL });
  try {
    await pgClient.connect();
    return pgClient;
  } catch (err) {
    if (err.code === 'ECONNREFUSED' || err.code === 'ENOTFOUND') {
      console.log('Skipping [' + (testName || 'Docker Postgres test') + ']: Local Docker Postgres unreachable on ' + DOCKER_PG_URL);
      t.skip('Local Docker Postgres unreachable on 127.0.0.1:54322');
      return null;
    }
    throw err;
  }
}

test('schema reflection: all user/profile linked tables accounted for in delete policy', async (t) => {
  const pgClient = await connectOrSkip(t, 'schema reflection: all user/profile linked tables accounted for in delete policy');
  if (!pgClient) return;

  try {
    const res = await pgClient.query(`
      SELECT DISTINCT table_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND (
          column_name LIKE '%user%'
          OR column_name LIKE '%patient%'
          OR column_name LIKE '%doctor%'
          OR column_name LIKE '%store%'
          OR column_name LIKE '%lab%'
          OR column_name LIKE '%ambulance%'
          OR column_name LIKE '%uid%'
        )
      ORDER BY table_name;
    `);

    const schemaTables = res.rows.map(r => r.table_name);

    // List of tables known and accounted for in delete_my_account.js
    // Either deleted directly, deleted via cascade, anonymized, or system logs
    const accountedTables = new Set([
      'admin_audit_logs',             // system log; admin_uid set null on delete
      'ambulance_broadcasts',         // deleted or cascade
      'ambulance_invites',            // deleted
      'ambulance_location_updates',    // cascade on ambulance_broadcasts
      'ambulance_locations',           // deleted / cascade
      'ambulance_private_settings',   // deleted
      'ambulance_requests',           // deleted
      'ambulance_trip_contacts',      // cascade on ambulance_broadcasts
      'ambulances',                   // deleted
      'appointments',                 // deleted
      'community_body_parts',         // system / global taxonomy
      'community_diagnoses',          // system / global taxonomy
      'community_lab_tests',          // system / global taxonomy
      'community_medicines',          // system / global taxonomy
      'community_radiology',          // system / global taxonomy
      'doctor_availability',          // deleted
      'doctor_blocked_dates',         // deleted
      'doctor_directory',             // deleted
      'doctor_education',             // deleted
      'doctor_facilities',            // deleted
      'doctor_invites',               // deleted
      'pharmacy_doctor_invites',      // deleted
      'doctor_private',               // deleted
      'doctors',                      // deleted
      'family_members',               // deleted
      'health_records',               // deleted
      'in_app_notifications',         // deleted
      'lab_bookings',                 // deleted
      'lab_catalog_tests',            // lab catalog
      'lab_connections',              // deleted
      'lab_orders',                   // deleted
      'labs',                         // deleted
      'medical_directory',            // public directory
      'medical_stores',               // deleted
      'patient_care_team',            // deleted / cascade
      'patient_doctor_links',         // deleted / cascade
      'patient_safe',                 // deleted / cascade
      'patients',                     // deleted
      'pharmacy_connections',         // deleted
      'pharmacy_deliveries',          // deleted
      'pharmacy_delivery_medicines',  // deleted / cascade
      'prescription_investigations',  // deleted / cascade
      'prescription_medicines',       // deleted / cascade
      'prescription_referrals',       // deleted / cascade
      'prescriptions',                // deleted
      'promoted_ads',                 // ads
      'razorpay_orders',              // anonymized (user_uid = null)
      'razorpay_payments',            // accounting audit trail
      'razorpay_webhook_events',      // immutable audit logs
      'referrals',                    // deleted
      'review_public',                // deleted / cascade
      'review_votes',                 // deleted
      'reviews',                      // deleted
      'security_events',              // security audit log (user_uid set null)
      'super_admins',                 // admin role registry
      'support_ticket_messages',      // deleted / cascade
      'support_tickets',              // deleted
      'user_devices',                 // deleted
      'users',                        // deleted
    ]);

    for (const table of schemaTables) {
      assert.ok(
        accountedTables.has(table),
        `Table '${table}' has user/profile columns but is not accounted for in account deletion audit!`
      );
    }
  } finally {
    await pgClient.end();
  }
});

test('Docker integration: full multi-table user graph deletion order succeeds without FK violations', async (t) => {
  const pgClient = await connectOrSkip(t, 'Docker integration: full multi-table user graph deletion order succeeds without FK violations');
  if (!pgClient) return;

  const ts = Date.now();
  const userId = `00000000-0000-0000-0000-${String(ts).slice(-12).padStart(12, '0')}`;
  const firebaseUid = `del_graph_fb_${ts}`;
  const patientId = `pat_del_${ts}`;
  const doctorId = `doc_del_${ts}`;
  const storeId = `store_del_${ts}`;
  const labId = `lab_del_${ts}`;
  const prescriptionId = `rx_del_${ts}`;
  const appointmentId = `apt_del_${ts}`;
  const deliveryId = `deliv_del_${ts}`;
  const ticketId = `tkt_del_${ts}`;
  const orderId = `order_del_${ts}`;

  try {
    // 1. Create user
    await pgClient.query(`
      INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile)
      VALUES ($1, $2, 'patient', $3, 'Graph Del User', $4, '9888877777')
      ON CONFLICT (id) DO NOTHING;
    `, [userId, firebaseUid, patientId, `graph_${ts}@test.invalid`]);

    // 2. Create patient & doctor
    await pgClient.query(`
      INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
      VALUES ($1, $2, 'Graph Patient', '9888877777')
      ON CONFLICT (patient_id) DO NOTHING;
    `, [patientId, userId]);

    await pgClient.query(`
      INSERT INTO public.doctors (doctor_id, name, specialization, mobile, email, qualification)
      VALUES ($1, 'Graph Doctor', 'General Medicine', '9777766666', $2, 'MBBS')
      ON CONFLICT (doctor_id) DO NOTHING;
    `, [doctorId, `doc_${ts}@example.com`]);

    await pgClient.query(`
      INSERT INTO public.medical_stores (store_id, store_name, owner_name, drug_license_number, phone, email)
      VALUES ($1, 'Graph Pharmacy', 'Owner Name', 'DL-12345', '9666655555', $2)
      ON CONFLICT (store_id) DO NOTHING;
    `, [storeId, `store_${ts}@example.com`]);

    await pgClient.query(`
      INSERT INTO public.labs (lab_id, lab_name, license_number, phone, email)
      VALUES ($1, 'Graph Lab', 'LAB-12345', '9555544444', $2)
      ON CONFLICT (lab_id) DO NOTHING;
    `, [labId, `lab_${ts}@example.com`]);

    // 3. Appointment
    await pgClient.query(`
      INSERT INTO public.appointments (appointment_id, patient_id, doctor_id, booked_by_uid, doctor_name, specialization, patient_name, patient_age, patient_gender, date_time, slot_label, visit_type, patient_status, doctor_status)
      VALUES ($1, $2, $3, $4, 'Graph Doctor', 'General Medicine', 'Graph Patient', 30, 'male', NOW(), '10:00 AM', 'newVisit', 'confirmed', 'confirmed')
      ON CONFLICT (appointment_id) DO NOTHING;
    `, [appointmentId, patientId, doctorId, userId]);

    // 4. Prescription with medicines
    await pgClient.query(`
      INSERT INTO public.prescriptions (prescription_id, patient_id, doctor_id, appointment_id, patient_name, patient_age, primary_diagnosis)
      VALUES ($1, $2, $3, $4, 'Graph Patient', 30, 'Fever')
      ON CONFLICT (prescription_id) DO NOTHING;
    `, [prescriptionId, patientId, doctorId, appointmentId]);

    await pgClient.query(`
      INSERT INTO public.prescription_medicines (prescription_id, medicine_entry_id, name, dosage, form, frequency, quantity, duration)
      VALUES ($1, $2, 'Paracetamol', '500mg', 'tablet', '1-0-1', '10', '3 days')
      ON CONFLICT DO NOTHING;
    `, [prescriptionId, `med_${ts}`]);

    // 5. Pharmacy Delivery (has RESTRICT foreign key to prescriptions and patients and store)
    await pgClient.query(`
      INSERT INTO public.pharmacy_deliveries (delivery_id, prescription_id, patient_id, store_id, doctor_id, doctor_name, store_name, patient_name, status)
      VALUES ($1, $2, $3, $4, $5, 'Graph Doctor', 'Graph Pharmacy', 'Graph Patient', 'delivered')
      ON CONFLICT (delivery_id) DO NOTHING;
    `, [deliveryId, prescriptionId, patientId, storeId, doctorId]);

    await pgClient.query(`
      INSERT INTO public.pharmacy_delivery_medicines (delivery_id, medicine_entry_id, availability)
      VALUES ($1, 'entry_1', 'available')
      ON CONFLICT DO NOTHING;
    `, [deliveryId]);

    // 6. Lab order & booking (has RESTRICT foreign key to patients)
    await pgClient.query(`
      INSERT INTO public.lab_orders (order_id, patient_id, doctor_id, lab_id, doctor_name, patient_name, patient_age, test_ids, test_names, status)
      VALUES ($1, $2, $3, $4, 'Graph Doctor', 'Graph Patient', 30, ARRAY['t1'], ARRAY['CBC'], 'ordered')
      ON CONFLICT (order_id) DO NOTHING;
    `, [`labord_${ts}`, patientId, doctorId, labId]);

    await pgClient.query(`
      INSERT INTO public.lab_bookings (booking_id, patient_id, lab_id, patient_name, patient_age, test_id, test_name, test_names, collection_type, date_time, slot_label, status)
      VALUES ($1, $2, $3, 'Graph Patient', 30, 't1', 'CBC', ARRAY['CBC'], 'labVisit', NOW(), '11:00 AM', 'confirmed')
      ON CONFLICT (booking_id) DO NOTHING;
    `, [`labbk_${ts}`, patientId, labId]);

    // 7. Referral (has RESTRICT foreign key to patients)
    await pgClient.query(`
      INSERT INTO public.referrals (referral_id, patient_id, from_doctor_id, to_doctor_id, from_doctor_name, to_doctor_name, to_specialization, patient_name, patient_age, reason)
      VALUES ($1, $2, $3, $3, 'Graph Doctor', 'Graph Doctor', 'General Medicine', 'Graph Patient', 30, 'Cardiology evaluation')
      ON CONFLICT (referral_id) DO NOTHING;
    `, [`ref_${ts}`, patientId, doctorId]);

    // 8. Support Ticket & message
    await pgClient.query(`
      INSERT INTO public.support_tickets (ticket_id, patient_id, user_id, issue_type, message, status)
      VALUES ($1, $2, $3, 'Technical', 'Login issue', 'open')
      ON CONFLICT (ticket_id) DO NOTHING;
    `, [ticketId, patientId, userId]);

    await pgClient.query(`
      INSERT INTO public.support_ticket_messages (message_id, ticket_id, sender_id, sender_name, sender_role, text)
      VALUES ($1, $2, $3, 'User', 'patient', 'Hello support')
      ON CONFLICT (message_id) DO NOTHING;
    `, [`msg_${ts}`, ticketId, userId]);

    // 9. Razorpay order
    await pgClient.query(`
      INSERT INTO public.razorpay_orders (order_id, user_uid, receipt, amount_paise, status)
      VALUES ($1, $2, 'rcpt_test', 50000, 'created')
      ON CONFLICT (order_id) DO NOTHING;
    `, [orderId, firebaseUid]);

    // 10. User device
    await pgClient.query(`
      INSERT INTO public.user_devices (user_id, fcm_token, platform)
      VALUES ($1, $2, 'android')
      ON CONFLICT DO NOTHING;
    `, [userId, `fcm_graph_${ts}`]);

    // ==========================================
    // EXECUTE COMPLETE ORDERED DELETION
    // ==========================================

    // Step 1: Pharmacy delivery medicines & deliveries (clears RESTRICT on prescriptions and patients)
    await pgClient.query('DELETE FROM public.pharmacy_delivery_medicines WHERE delivery_id = $1;', [deliveryId]);
    await pgClient.query('DELETE FROM public.pharmacy_deliveries WHERE delivery_id = $1;', [deliveryId]);

    // Step 2: Lab orders & bookings (clears RESTRICT on patients)
    await pgClient.query('DELETE FROM public.lab_orders WHERE patient_id = $1;', [patientId]);
    await pgClient.query('DELETE FROM public.lab_bookings WHERE patient_id = $1;', [patientId]);

    // Step 3: Referrals (clears RESTRICT on patients)
    await pgClient.query('DELETE FROM public.referrals WHERE patient_id = $1;', [patientId]);

    // Step 4: Prescription medicines & prescriptions
    await pgClient.query('DELETE FROM public.prescription_medicines WHERE prescription_id = $1;', [prescriptionId]);
    await pgClient.query('DELETE FROM public.prescriptions WHERE prescription_id = $1;', [prescriptionId]);

    // Step 5: Appointments, Patient personal rows, and Patients
    await pgClient.query('DELETE FROM public.appointments WHERE patient_id = $1;', [patientId]);
    await pgClient.query('DELETE FROM public.patients WHERE patient_id = $1;', [patientId]);

    // Step 6: Support ticket messages & tickets
    await pgClient.query('DELETE FROM public.support_ticket_messages WHERE ticket_id = $1;', [ticketId]);
    await pgClient.query('DELETE FROM public.support_tickets WHERE ticket_id = $1;', [ticketId]);

    // Step 7: User devices & notifications
    await pgClient.query('DELETE FROM public.user_devices WHERE user_id = $1;', [userId]);

    // Step 8: Anonymize financial records
    await pgClient.query('UPDATE public.razorpay_orders SET user_uid = NULL WHERE user_uid = $1;', [firebaseUid]);

    // Step 9: Delete user
    await pgClient.query('DELETE FROM public.users WHERE id = $1;', [userId]);

    // ==========================================
    // ASSERTIONS
    // ==========================================
    const checkUser = await pgClient.query('SELECT id FROM public.users WHERE id = $1;', [userId]);
    assert.equal(checkUser.rowCount, 0, 'User must be deleted');

    const checkPatient = await pgClient.query('SELECT patient_id FROM public.patients WHERE patient_id = $1;', [patientId]);
    assert.equal(checkPatient.rowCount, 0, 'Patient must be deleted');

    const checkPresc = await pgClient.query('SELECT prescription_id FROM public.prescriptions WHERE prescription_id = $1;', [prescriptionId]);
    assert.equal(checkPresc.rowCount, 0, 'Prescription must be deleted');

    const checkDelivery = await pgClient.query('SELECT delivery_id FROM public.pharmacy_deliveries WHERE delivery_id = $1;', [deliveryId]);
    assert.equal(checkDelivery.rowCount, 0, 'Delivery must be deleted');

    const checkOrder = await pgClient.query('SELECT user_uid FROM public.razorpay_orders WHERE order_id = $1;', [orderId]);
    assert.equal(checkOrder.rows[0].user_uid, null, 'Payment order must be anonymized');
  } finally {
    // Cleanup reference entities
    await pgClient.query('DELETE FROM public.razorpay_orders WHERE order_id = $1;', [orderId]).catch(() => {});
    await pgClient.query('DELETE FROM public.labs WHERE lab_id = $1;', [labId]).catch(() => {});
    await pgClient.query('DELETE FROM public.medical_stores WHERE store_id = $1;', [storeId]).catch(() => {});
    await pgClient.query('DELETE FROM public.doctors WHERE doctor_id = $1;', [doctorId]).catch(() => {});
    await pgClient.end();
  }
});
