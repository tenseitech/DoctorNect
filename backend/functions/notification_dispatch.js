'use strict';

/**
 * Maps Postgres row change payloads to FCM sends (shared by webhook + outbox worker).
 */

async function dispatchDatabaseChangeEvent({
  type,
  table,
  record,
  oldRecord,
  sendFcm,
  dbStub = null,
}) {
  if (!sendFcm || !table || !type) return { sent: 0 };

  let sent = 0;
  const sendOne = async (payload) => {
    const ok = await sendFcm(dbStub, { ...payload, forceSupabase: true });
    if (ok) sent += 1;
  };

  if (table === 'appointments') {
    if (type === 'INSERT' && record) {
      const doctorId = record.doctor_id;
      const patientName = String(record.patient_name || 'Patient').trim();
      const appointmentId = record.appointment_id;
      if (doctorId) {
        await sendOne({
          collection: 'doctors',
          docId: doctorId,
          title: 'New Appointment Booked',
          body: `${patientName} booked an appointment for ${record.slot_label || 'upcoming slot'}.`,
          data: {
            type: 'appointment_new',
            appointmentId: String(appointmentId),
            patientName,
            doctorTrigger: 'newAppointmentBooked',
          },
          androidChannelId: 'doctor_appointments',
          logLabel: `doctor ${doctorId} appointment ${appointmentId}`,
        });
      }
    } else if (type === 'UPDATE' && record && oldRecord) {
      if (record.doctor_status !== oldRecord.doctor_status) {
        const patientId = record.patient_id;
        const doctorName = String(record.doctor_name || 'Doctor').trim();
        const appointmentId = record.appointment_id;
        const status = record.doctor_status === 'confirmed' ? 'confirmed' : 'cancelled';
        const title = status === 'confirmed' ? 'Appointment Confirmed' : 'Appointment Declined';
        const body =
          status === 'confirmed'
            ? `Dr. ${doctorName} confirmed your appointment.`
            : `Dr. ${doctorName} could not accept your appointment.`;
        if (patientId) {
          await sendOne({
            collection: 'patients',
            docId: patientId,
            title,
            body,
            data: {
              type: 'appointment_status_update',
              appointmentId: String(appointmentId),
              status,
              doctorName,
              patientTrigger:
                status === 'confirmed' ? 'appointmentConfirmedByDoctor' : 'appointmentDeclinedByDoctor',
            },
            androidChannelId: 'patient_appointments',
            logLabel: `patient ${patientId} appointment ${appointmentId}`,
          });
        }
      }
    }
  } else if (table === 'referrals' && type === 'INSERT' && record) {
    const toDoctorId = record.to_doctor_id;
    const referringDoctor = String(record.from_doctor_name || 'A doctor').trim();
    const referralId = record.referral_id;
    if (toDoctorId) {
      await sendOne({
        collection: 'doctors',
        docId: toDoctorId,
        title: 'New Patient Referral',
        body: `${referringDoctor} referred a patient to you.`,
        data: {
          type: 'referral_received',
          referralId: String(referralId),
          doctorTrigger: 'patientReferredToMe',
        },
        androidChannelId: 'doctor_appointments',
        logLabel: `doctor ${toDoctorId} referral ${referralId}`,
      });
    }
  } else if (table === 'pharmacy_deliveries' && record) {
    if (type === 'INSERT') {
      const storeId = record.store_id;
      const doctorName = String(record.doctor_name || 'Doctor').trim();
      const patientName = String(record.patient_name || 'Patient').trim();
      if (storeId) {
        await sendOne({
          collection: 'medical_stores',
          docId: storeId,
          title: 'New Prescription Delivery',
          body: `${doctorName} sent a prescription for ${patientName}.`,
          data: {
            type: 'pharmacy_delivery_new',
            deliveryId: String(record.delivery_id || ''),
            prescriptionId: String(record.prescription_id || ''),
          },
          androidChannelId: 'pharmacy_orders',
          logLabel: `store ${storeId} pharmacy delivery ${record.delivery_id}`,
        });
      }
    } else if (type === 'UPDATE' && oldRecord && record.status === 'dispensed' && oldRecord.status !== 'dispensed') {
      const patientId = record.patient_id;
      const storeName = String(record.store_name || 'Pharmacy').trim();
      if (patientId) {
        await sendOne({
          collection: 'patients',
          docId: patientId,
          title: 'Medicines Ready',
          body: `${storeName} marked your order as dispensed.`,
          data: {
            type: 'pharmacy_delivery_update',
            status: 'dispensed',
            deliveryId: String(record.delivery_id || ''),
          },
          androidChannelId: 'patient_orders',
          logLabel: `patient ${patientId} pharmacy delivery ${record.delivery_id}`,
        });
      }
    }
  } else if (table === 'lab_bookings' && record) {
    if (type === 'INSERT') {
      const labId = record.lab_id;
      const patientName = String(record.patient_name || 'Patient').trim();
      const testName = String(record.test_name || 'Lab test').trim();
      if (labId) {
        await sendOne({
          collection: 'labs',
          docId: labId,
          title: 'New Lab Booking',
          body: `${patientName} booked ${testName}.`,
          data: {
            type: 'lab_booking_new',
            bookingId: String(record.booking_id || ''),
          },
          androidChannelId: 'lab_bookings',
          logLabel: `lab ${labId} booking ${record.booking_id}`,
        });
      }
    } else if (type === 'UPDATE' && oldRecord && record.status === 'completed' && oldRecord.status !== 'completed') {
      const patientId = record.patient_id;
      const labName = String(record.lab_name || 'Lab').trim();
      const testName = String(record.test_name || 'your test').trim();
      if (patientId) {
        await sendOne({
          collection: 'patients',
          docId: patientId,
          title: 'Lab Report Ready',
          body: `${labName} completed ${testName}.`,
          data: {
            type: 'lab_booking_update',
            status: 'completed',
            bookingId: String(record.booking_id || ''),
          },
          androidChannelId: 'patient_labs',
          logLabel: `patient ${patientId} lab booking ${record.booking_id}`,
        });
      }
    }
  } else if (table === 'ambulance_broadcasts' && type === 'UPDATE' && record && oldRecord) {
    if (record.status === 'accepted' && oldRecord.status !== 'accepted') {
      const patientId = record.patient_id;
      if (patientId) {
        await sendOne({
          collection: 'patients',
          docId: patientId,
          title: 'Ambulance Assigned',
          body: 'A driver accepted your ambulance request.',
          data: {
            type: 'ambulance_accepted',
            broadcastId: String(record.broadcast_id || ''),
          },
          androidChannelId: 'patient_ambulance',
          logLabel: `patient ${patientId} broadcast ${record.broadcast_id}`,
        });
      }
    }
  }

  return { sent };
}

function buildDedupeKey({ table, type, record, payload }) {
  const crypto = require('crypto');
  const entityId = String(
    record?.appointment_id ||
      record?.referral_id ||
      record?.delivery_id ||
      record?.booking_id ||
      record?.broadcast_id ||
      record?.id ||
      payload?.id ||
      'event',
  );
  const eventTime = String(record?.updated_at || record?.created_at || payload?.created_at || '');
  const eventKey = `${table}:${type}:${entityId}:${eventTime}`;
  return crypto.createHash('sha256').update(eventKey).digest('hex');
}

function notificationDispatchMode() {
  return String(process.env.NOTIFICATION_DISPATCH_MODE || 'outbox').trim().toLowerCase();
}

module.exports = {
  dispatchDatabaseChangeEvent,
  buildDedupeKey,
  notificationDispatchMode,
};
