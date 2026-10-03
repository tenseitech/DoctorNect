const { FieldValue } = require('firebase-admin/firestore');

const IN_APP_NOTIFICATIONS = 'in_app_notifications';
const DOCTORS = 'doctors';
const PATIENTS = 'patients';

function sanitizeDocIdPart(value) {
  return String(value || '')
    .trim()
    .replace(/[/]/g, '_')
    .slice(0, 200);
}

/**
 * Resolve the doctor's Firebase Auth uid from their profile id.
 */
async function resolveDoctorRecipientUid(db, doctorId) {
  const normalizedDoctorId = String(doctorId || '').trim();
  if (!normalizedDoctorId) return null;

  const doctorSnap = await db.collection(DOCTORS).doc(normalizedDoctorId).get();
  if (!doctorSnap.exists) return null;

  const ownerUid = String(doctorSnap.data()?.ownerUid || '').trim();
  return ownerUid || null;
}

/**
 * Resolve the patient's Firebase Auth uid from their profile id.
 */
async function resolvePatientRecipientUid(db, patientId) {
  const normalizedPatientId = String(patientId || '').trim();
  if (!normalizedPatientId) return null;

  const patientSnap = await db.collection(PATIENTS).doc(normalizedPatientId).get();
  if (!patientSnap.exists) return null;

  const ownerUid = String(patientSnap.data()?.ownerUid || '').trim();
  return ownerUid || null;
}

/**
 * Idempotent in-app notification write using a deterministic document id.
 */
async function createInAppNotification(db, payload) {
  const recipientUid = String(payload.recipientUid || '').trim();
  const dedupeKey = String(payload.dedupeKey || '').trim();
  if (!recipientUid || !dedupeKey) return null;

  const docId = `${sanitizeDocIdPart(recipientUid)}_${sanitizeDocIdPart(dedupeKey)}`;
  const ref = db.collection(IN_APP_NOTIFICATIONS).doc(docId);

  const data = {
    recipientUid,
    recipientRole: payload.recipientRole,
    recipientProfileId: payload.recipientProfileId,
    title: payload.title,
    body: payload.body,
    type: payload.type,
    target: payload.target || null,
    targetId: payload.targetId || null,
    dedupeKey,
    doctorTrigger: payload.doctorTrigger || null,
    patientTrigger: payload.patientTrigger || null,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
    sourceEvent: payload.sourceEvent,
    sourceId: payload.sourceId,
  };

  await ref.set(data, { merge: true });
  return docId;
}

function findNewOutOfStockMedicineLines(beforeLines, afterLines) {
  const beforeAvailabilityById = new Map();
  for (const line of beforeLines || []) {
    if (!line || !line.medicineEntryId) continue;
    beforeAvailabilityById.set(String(line.medicineEntryId), String(line.availability || ''));
  }

  const newlyOutOfStock = [];
  for (const line of afterLines || []) {
    if (!line || !line.medicineEntryId) continue;
    const medicineEntryId = String(line.medicineEntryId);
    const afterAvailability = String(line.availability || '');
    const beforeAvailability = beforeAvailabilityById.get(medicineEntryId) || '';
    if (afterAvailability === 'outOfStock' && beforeAvailability !== 'outOfStock') {
      newlyOutOfStock.push(medicineEntryId);
    }
  }
  return newlyOutOfStock;
}

async function writeInAppNotification(db, eventName, payload, logFields = {}) {
  if (!payload) return null;

  let recipientUid = null;
  if (payload.recipientRole === 'doctor') {
    recipientUid = await resolveDoctorRecipientUid(db, payload.recipientProfileId);
  } else if (payload.recipientRole === 'patient') {
    recipientUid = await resolvePatientRecipientUid(db, payload.recipientProfileId);
  }

  console.log(`[in-app] ${eventName}`, {
    ...logFields,
    patientId:
      logFields.patientId
      ?? (payload.recipientRole === 'patient' ? payload.recipientProfileId : undefined),
    doctorId:
      logFields.doctorId
      ?? (payload.recipientRole === 'doctor' ? payload.recipientProfileId : undefined),
    recipientUid,
    recipientProfileId: payload.recipientProfileId,
    dedupeKey: payload.dedupeKey,
  });

  if (!recipientUid) return null;

  try {
    return await createInAppNotification(db, { ...payload, recipientUid });
  } catch (err) {
    console.error(`In-app notification create failed for ${eventName}`, logFields, err);
    return null;
  }
}

function buildDoctorNewAppointmentNotification(appointment, firestoreDocId) {
  const doctorStatus = String(appointment.doctorStatus || '').trim();
  const patientName = String(appointment.patientName || 'Patient').trim() || 'Patient';
  const slotLabel = String(appointment.slotLabel || 'Scheduled time').trim() || 'Scheduled time';
  const appointmentId = String(appointment.appointmentId || '').trim();
  const doctorId = String(appointment.doctorId || '').trim();

  if (!doctorId) return null;

  if (doctorStatus === 'confirmed') {
    return {
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'New appointment',
      body: `${patientName} · ${slotLabel}`,
      type: 'booking',
      target: 'appointmentDetail',
      targetId: appointmentId || null,
      dedupeKey: appointmentId ? `d_appt_new_${appointmentId}` : `d_appt_new_${firestoreDocId}`,
      doctorTrigger: 'newAppointmentBooked',
      sourceEvent: 'appointment.created',
      sourceId: firestoreDocId,
    };
  }

  if (doctorStatus === 'pendingRequest') {
    return {
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'New request',
      body: `${patientName} · ${slotLabel}`,
      type: 'booking',
      target: 'appointmentDetail',
      targetId: appointmentId || null,
      dedupeKey: appointmentId
        ? `d_appt_request_${appointmentId}`
        : `d_appt_request_${firestoreDocId}`,
      doctorTrigger: 'newAppointmentBooked',
      sourceEvent: 'appointment.created',
      sourceId: firestoreDocId,
    };
  }

  return null;
}

function buildPatientAppointmentStatusNotification(before, after, firestoreDocId) {
  const beforeStatus = String(before?.doctorStatus || '').trim();
  const afterStatus = String(after?.doctorStatus || '').trim();
  if (beforeStatus !== 'pendingRequest') return null;

  const patientId = String(after.patientId || '').trim();
  if (!patientId) return null;

  const doctorName = String(after.doctorName || 'Doctor').trim() || 'Doctor';
  const slotLabel = String(after.slotLabel || 'Scheduled time').trim() || 'Scheduled time';
  const appointmentId = String(after.appointmentId || firestoreDocId).trim() || firestoreDocId;
  const tokenNumber = after.tokenNumber;
  const tokenSuffix =
    tokenNumber != null && String(tokenNumber).trim() !== ''
      ? ` · Token #${tokenNumber}`
      : '';

  if (afterStatus === 'confirmed') {
    return {
      recipientRole: 'patient',
      recipientProfileId: patientId,
      title: 'Appointment accepted',
      body: `Dr. ${doctorName} confirmed your visit · ${slotLabel}${tokenSuffix}`,
      type: 'booking',
      target: 'appointments',
      targetId: appointmentId,
      dedupeKey: `p_appt_accepted_${appointmentId}`,
      patientTrigger: 'bookingConfirmed',
      sourceEvent: 'appointment.status_updated',
      sourceId: firestoreDocId,
    };
  }

  if (afterStatus === 'cancelled') {
    return {
      recipientRole: 'patient',
      recipientProfileId: patientId,
      title: 'Appointment declined',
      body: `Dr. ${doctorName} could not accept your request.`,
      type: 'cancellation',
      target: 'appointments',
      targetId: appointmentId,
      dedupeKey: `p_appt_declined_${appointmentId}`,
      patientTrigger: 'doctorCancelled',
      sourceEvent: 'appointment.status_updated',
      sourceId: firestoreDocId,
    };
  }

  return null;
}

function buildPatientLabBookingStatusNotification(booking, firestoreBookingId) {
  const status = String(booking.status || '').trim();
  const patientId = String(booking.patientId || '').trim();
  if (!patientId) return null;

  const labName = String(booking.partnerLab || booking.labName || 'Lab').trim() || 'Lab';
  const testName = String(booking.testName || 'lab test').trim() || 'lab test';
  const slotLabel = String(booking.slotLabel || '').trim();
  const bookingId = String(booking.bookingId || firestoreBookingId).trim() || firestoreBookingId;

  if (status === 'confirmed') {
    const body = slotLabel
      ? `${labName} confirmed ${testName} · ${slotLabel}`
      : `${labName} confirmed ${testName}`;
    return {
      recipientRole: 'patient',
      recipientProfileId: patientId,
      title: 'Lab booking accepted',
      body,
      type: 'labReport',
      target: 'labBooking',
      targetId: bookingId,
      dedupeKey: `p_lab_accept_${bookingId}`,
      patientTrigger: 'labBookingUpdate',
      sourceEvent: 'lab_booking.status_updated',
      sourceId: firestoreBookingId,
    };
  }

  if (status === 'declined') {
    return {
      recipientRole: 'patient',
      recipientProfileId: patientId,
      title: 'Lab booking declined',
      body: `${labName} could not accept ${testName}`,
      type: 'labReport',
      target: 'labBooking',
      targetId: bookingId,
      dedupeKey: `p_lab_decline_${bookingId}`,
      patientTrigger: 'labBookingUpdate',
      sourceEvent: 'lab_booking.status_updated',
      sourceId: firestoreBookingId,
    };
  }

  return null;
}

function buildPatientLabReportReadyNotification(booking, firestoreBookingId) {
  const patientId = String(booking.patientId || '').trim();
  if (!patientId) return null;

  const labName = String(booking.partnerLab || booking.labName || 'Lab').trim() || 'Lab';
  const testName = String(booking.testName || 'lab test').trim() || 'lab test';
  const bookingId = String(booking.bookingId || firestoreBookingId).trim() || firestoreBookingId;

  return {
    recipientRole: 'patient',
    recipientProfileId: patientId,
    title: 'Lab report ready',
    body: `${labName} shared your ${testName} report`,
    type: 'labReport',
    target: 'labReports',
    targetId: bookingId,
    dedupeKey: `p_lab_report_${bookingId}`,
    patientTrigger: 'labReportReady',
    sourceEvent: 'lab_booking.report_ready',
    sourceId: firestoreBookingId,
  };
}

function buildPatientLabOrderNotification(order, firestoreOrderId) {
  const patientId = String(order.patientId || '').trim();
  if (!patientId) return null;

  const doctorName = String(order.doctorName || 'Doctor').trim() || 'Doctor';
  const orderId = String(order.orderId || firestoreOrderId).trim() || firestoreOrderId;
  const testNames = Array.isArray(order.testNames)
    ? order.testNames.map((name) => String(name).trim()).filter(Boolean)
    : [];
  const testsLabel = testNames.length > 0 ? testNames.join(', ') : 'lab tests';
  const labName = String(order.labName || '').trim();
  const labSuffix = labName ? ` · ${labName}` : '';

  return {
    recipientRole: 'patient',
    recipientProfileId: patientId,
    title: 'Lab tests ordered',
    body: `Dr. ${doctorName} ordered: ${testsLabel}${labSuffix}`,
    type: 'labReport',
    target: 'labReports',
    targetId: orderId,
    dedupeKey: `p_lab_order_${orderId}`,
    patientTrigger: 'labBookingUpdate',
    sourceEvent: 'lab_order.created',
    sourceId: firestoreOrderId,
  };
}

function buildDoctorLabConnectionNotification(before, after, connectionId) {
  if (!after) return null;

  const doctorId = String(after.doctorId || '').trim();
  if (!doctorId) return null;

  const status = String(after.status || '').trim();
  const requestedBy = String(after.requestedBy || '').trim();
  const labName = String(after.labName || 'Lab').trim() || 'Lab';
  const beforeStatus = before ? String(before.status || '').trim() : '';

  if ((!before || !beforeStatus) && status === 'pending' && requestedBy === 'lab') {
    return {
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'Lab connection request',
      body: `${labName} wants to connect with you`,
      type: 'system',
      targetId: connectionId,
      dedupeKey: `d_lab_conn_${connectionId}`,
      sourceEvent: 'lab_connection.requested',
      sourceId: connectionId,
    };
  }

  if (beforeStatus === 'pending' && status === 'active' && requestedBy === 'doctor') {
    return {
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'Connection approved',
      body: `${labName} accepted your invite`,
      type: 'system',
      targetId: connectionId,
      dedupeKey: `d_lab_conn_approved_${connectionId}`,
      sourceEvent: 'lab_connection.approved',
      sourceId: connectionId,
    };
  }

  if (beforeStatus === 'pending' && status === 'rejected' && requestedBy === 'doctor') {
    return {
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'Connection rejected',
      body: `${labName} rejected your invite`,
      type: 'system',
      targetId: connectionId,
      dedupeKey: `d_lab_conn_rejected_${connectionId}`,
      sourceEvent: 'lab_connection.rejected',
      sourceId: connectionId,
    };
  }

  return null;
}

function buildDoctorPharmacyConnectionNotification(before, after, connectionId) {
  if (!after) return null;

  const doctorId = String(after.doctorId || '').trim();
  if (!doctorId) return null;

  const status = String(after.status || '').trim();
  const requestedBy = String(after.requestedBy || '').trim();
  const storeName = String(after.storeName || 'Medical Store').trim() || 'Medical Store';
  const beforeStatus = before ? String(before.status || '').trim() : '';

  if ((!before || !beforeStatus) && status === 'pending' && requestedBy === 'store') {
    return {
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'Connection request',
      body: `${storeName} wants to connect with you`,
      type: 'system',
      targetId: connectionId,
      dedupeKey: `d_pharm_conn_${connectionId}`,
      sourceEvent: 'pharmacy_connection.requested',
      sourceId: connectionId,
    };
  }

  if (beforeStatus === 'pending' && status === 'active' && requestedBy === 'doctor') {
    return {
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'Connection approved',
      body: `${storeName} accepted your invite`,
      type: 'system',
      targetId: connectionId,
      dedupeKey: `d_pharm_conn_approved_${connectionId}`,
      sourceEvent: 'pharmacy_connection.approved',
      sourceId: connectionId,
    };
  }

  if (beforeStatus === 'pending' && status === 'rejected' && requestedBy === 'doctor') {
    return {
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'Connection rejected',
      body: `${storeName} rejected your invite`,
      type: 'system',
      targetId: connectionId,
      dedupeKey: `d_pharm_conn_rejected_${connectionId}`,
      sourceEvent: 'pharmacy_connection.rejected',
      sourceId: connectionId,
    };
  }

  return null;
}

function buildPatientPharmacyDeliveryCreatedNotification(delivery, deliveryId) {
  const patientId = String(delivery.patientId || '').trim();
  if (!patientId) return null;

  const doctorName = String(delivery.doctorName || 'Doctor').trim() || 'Doctor';
  const storeName = String(delivery.storeName || 'Pharmacy').trim() || 'Pharmacy';
  const prescriptionId = String(delivery.prescriptionId || '').trim();
  const targetId = prescriptionId || deliveryId;

  return {
    recipientRole: 'patient',
    recipientProfileId: patientId,
    title: 'Sent to pharmacy',
    body: `Dr. ${doctorName} sent your prescription to ${storeName}`,
    type: 'prescription',
    target: 'prescriptions',
    targetId,
    dedupeKey: prescriptionId
      ? `p_rx_pharm_sent_${prescriptionId}`
      : `p_rx_pharm_sent_${deliveryId}`,
    patientTrigger: 'pharmacyDeliveryUpdate',
    sourceEvent: 'pharmacy_delivery.created',
    sourceId: deliveryId,
  };
}

function buildDoctorPharmacyDeliveryUpdatedNotifications(before, after, deliveryId) {
  if (!after) return [];

  const doctorId = String(after.doctorId || '').trim();
  if (!doctorId) return [];

  const storeName = String(after.storeName || 'Pharmacy').trim() || 'Pharmacy';
  const prescriptionId = String(after.prescriptionId || '').trim();
  const beforeStatus = before ? String(before.status || '').trim() : '';
  const afterStatus = String(after.status || '').trim();
  const notifications = [];

  if (beforeStatus === 'sent' && afterStatus === 'viewed') {
    notifications.push({
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'Prescription viewed',
      body: `${storeName} viewed prescription ${prescriptionId || deliveryId}`,
      type: 'prescription',
      targetId: deliveryId,
      dedupeKey: `d_pharm_view_${deliveryId}`,
      sourceEvent: 'pharmacy_delivery.viewed',
      sourceId: deliveryId,
    });
  }

  if (
    beforeStatus !== afterStatus
    && (afterStatus === 'dispensed' || afterStatus === 'partiallyDispensed')
  ) {
    notifications.push({
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'Prescription dispensed',
      body: `${storeName} dispensed prescription ${prescriptionId || deliveryId}`,
      type: 'prescription',
      targetId: deliveryId,
      dedupeKey: `d_pharm_disp_${deliveryId}`,
      sourceEvent: 'pharmacy_delivery.dispensed',
      sourceId: deliveryId,
    });
  }

  for (const medicineEntryId of findNewOutOfStockMedicineLines(
    before?.medicineLines,
    after.medicineLines,
  )) {
    notifications.push({
      recipientRole: 'doctor',
      recipientProfileId: doctorId,
      title: 'Medicine out of stock',
      body: `${storeName} marked a medicine as out of stock`,
      type: 'prescription',
      targetId: deliveryId,
      dedupeKey: `d_pharm_oos_${deliveryId}_${medicineEntryId}`,
      sourceEvent: 'pharmacy_delivery.out_of_stock',
      sourceId: deliveryId,
    });
  }

  return notifications;
}

function buildPatientPharmacyDeliveryUpdatedNotification(before, after, deliveryId) {
  if (!after) return null;

  const patientId = String(after.patientId || '').trim();
  if (!patientId) return null;

  const beforeStatus = before ? String(before.status || '').trim() : '';
  const afterStatus = String(after.status || '').trim();
  if (beforeStatus === afterStatus) return null;
  if (afterStatus !== 'dispensed' && afterStatus !== 'partiallyDispensed') return null;

  const storeName = String(after.storeName || 'Pharmacy').trim() || 'Pharmacy';
  const prescriptionId = String(after.prescriptionId || '').trim();
  const partial = afterStatus === 'partiallyDispensed';
  const targetId = prescriptionId || deliveryId;

  return {
    recipientRole: 'patient',
    recipientProfileId: patientId,
    title: partial ? 'Medicines partially ready' : 'Medicines ready',
    body: partial
      ? `Some medicines are ready at ${storeName}`
      : `Your medicines are ready for pickup at ${storeName}`,
    type: 'prescription',
    target: 'prescriptions',
    targetId,
    dedupeKey: partial
      ? `p_rx_pharm_ready_partial_${targetId}`
      : `p_rx_pharm_ready_${targetId}`,
    patientTrigger: 'pharmacyDeliveryUpdate',
    sourceEvent: 'pharmacy_delivery.dispensed',
    sourceId: deliveryId,
  };
}

function buildDoctorReferralReceivedNotification(referral, firestoreDocId) {
  const toDoctorId = String(referral.toDoctorId || '').trim();
  const fromDoctorId = String(referral.fromDoctorId || '').trim();
  const fromDoctorName = String(referral.fromDoctorName || 'A doctor').trim() || 'A doctor';
  const patientName = String(referral.patientName || 'Patient').trim() || 'Patient';
  const referralId = String(referral.referralId || firestoreDocId || '').trim();

  if (!toDoctorId || !referralId || toDoctorId === fromDoctorId) return null;

  return {
    recipientRole: 'doctor',
    recipientProfileId: toDoctorId,
    title: 'New referral',
    body: `Dr. ${fromDoctorName} referred ${patientName} to you`,
    type: 'appointment',
    target: 'patients',
    targetId: referralId,
    dedupeKey: `d_referral_${referralId}`,
    doctorTrigger: 'patientReferredToMe',
    sourceEvent: 'referral.created',
    sourceId: firestoreDocId,
  };
}

module.exports = {
  resolveDoctorRecipientUid,
  resolvePatientRecipientUid,
  createInAppNotification,
  writeInAppNotification,
  buildDoctorNewAppointmentNotification,
  buildDoctorReferralReceivedNotification,
  buildPatientAppointmentStatusNotification,
  buildPatientLabBookingStatusNotification,
  buildPatientLabReportReadyNotification,
  buildPatientLabOrderNotification,
  buildDoctorLabConnectionNotification,
  buildDoctorPharmacyConnectionNotification,
  buildPatientPharmacyDeliveryCreatedNotification,
  buildDoctorPharmacyDeliveryUpdatedNotifications,
  buildPatientPharmacyDeliveryUpdatedNotification,
};
