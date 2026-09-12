const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
initializeApp();

const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { sendFcmIfTokenExists, resolveAmbulanceDriverToken } = require('./fcm_push');
const {
  RULES,
  VITAL_THRESHOLDS,
  runRule,
  runVitalAdvisory,
  validateFields,
} = require('./validation_rules');
const {
  sendUserRegistrationOtp,
  verifyUserRegistrationOtp,
  finalizePatientOtpVerification,
  approveUserAccount,
  approvePatientAccount,
  resetAmbulanceDriverPin,
  completeAmbulanceMobileOtpLogin,
  resetUserPasswordWithOtp,
  completeMobileOtpLogin,
  assertLoginAllowed,
  recordFailedLogin,
  clearFailedLogins,
  hashAmbulancePin,
  ambulancePinMatches,
  isPlayReviewMobileInput,
  isDemoMobileInput,
  lookupMobileRegistration,
} = require('./registration_otp');
const {
  resolveDoctorRecipientUid,
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
} = require('./in_app_notifications');
const {
  createRazorpayOrder,
  verifyRazorpayPayment,
  expirePromotedAds,
} = require('./promoted_ads');
const { MSG91_SECRETS } = require('./secure_config');
const {
  sanitizeRuleParams,
  requireKnownRule,
  requireDocId,
  requireUsername,
  requirePin,
  requireAmbulancePassword,
  requireStars,
  sanitizeReview,
  sanitizePlainText,
  requireEmail,
  requireString,
  requireHexLikeToken,
  requireInviteToken,
} = require('./input_sanitize');
const {
  logAuthAttempt,
  logUnusualTraffic,
  withSecurityLogging,
} = require('./security_logger');
const { assertProductionSecrets } = require('./secure_config');
const {
  enforceAbuseLimit,
  assertAppCheck,
  withAbuseProtection,
} = require('./abuse_rate_limit');

assertProductionSecrets();

/** Match deployed regions: Firestore triggers in asia-south2, callables in asia-south1. */
const FIRESTORE_TRIGGER_REGION = 'asia-south2';
const CALLABLE_REGION = 'asia-south1';

/** MSG91 callable options (asia-south1) — region + Secret Manager secrets. */
const MSG91_VPC_OPTIONS = {
  region: 'asia-south1',
  secrets: MSG91_SECRETS,
};

/** Set ENFORCE_OTP_APP_CHECK=false in functions/.env only while App Check is being configured. */
const ENFORCE_OTP_APP_CHECK = String(process.env.ENFORCE_OTP_APP_CHECK || 'true')
  .trim()
  .toLowerCase() !== 'false';

/** Broader App Check for abuse-sensitive callables (defaults to same as OTP). */
const ENFORCE_ABUSE_APP_CHECK = String(
  process.env.ENFORCE_ABUSE_APP_CHECK || process.env.ENFORCE_OTP_APP_CHECK || 'true',
)
  .trim()
  .toLowerCase() !== 'false';

function db() {
  return getFirestore();
}

/** Compose security logging + abuse limits for callables. */
function protectCallable(name, options, handler) {
  const opts = typeof options === 'function'
    ? { category: 'api', handler: options }
    : { ...options, handler };
  const {
    category = 'api',
    enforceAppCheck = ENFORCE_ABUSE_APP_CHECK,
    identifierFromRequest,
    message,
    handler: h,
  } = opts;

  return withSecurityLogging(
    name,
    withAbuseProtection(
      db,
      { category, enforceAppCheck, identifierFromRequest, message },
      h,
    ),
  );
}

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }
}

function getCallableClientIp(request) {
  const raw = request.rawRequest;
  if (!raw) return 'unknown';

  const forwarded = raw.headers?.['x-forwarded-for'];
  if (forwarded) {
    return String(forwarded).split(',')[0].trim();
  }

  return raw.ip || raw.socket?.remoteAddress || 'unknown';
}

function isAmbulancePinHash(storedPin) {
  const stored = String(storedPin || '').trim();
  if (stored.startsWith('pbkdf2$')) return true;
  return stored.length === 64 && /^[a-f0-9]{64}$/i.test(stored);
}

function pinMatches(storedPin, enteredPin) {
  return ambulancePinMatches(storedPin, enteredPin);
}

async function readAmbulancePinHash(db, driverId) {
  const privateSnap = await db
    .collection('ambulances')
    .doc(driverId)
    .collection('private')
    .doc('settings')
    .get();
  if (privateSnap.exists) {
    return privateSnap.data()?.pin || '';
  }
  const legacySnap = await db.collection('ambulances').doc(driverId).get();
  return legacySnap.data()?.pin || '';
}

async function findAmbulanceByUsername(db, username) {
  const normalized = String(username || '').trim().toLowerCase();
  if (normalized.length < 3) return null;

  const snapshot = await db
    .collection('ambulances')
    .where('username', '==', normalized)
    .limit(1)
    .get();

  if (snapshot.empty) return null;

  const doc = snapshot.docs[0];
  return { id: doc.id, data: doc.data(), username: normalized };
}

async function verifyAmbulanceCredentials(db, username, pin) {
  const pinNorm = String(pin || '').trim();
  if (pinNorm.length < 6) {
    return { ok: false, invalidCredentials: true };
  }

  const found = await findAmbulanceByUsername(db, username);
  if (!found) {
    return { ok: false, invalidCredentials: true };
  }

  const storedPin = await readAmbulancePinHash(db, found.id);
  if (!isAmbulancePinHash(storedPin)) {
    if (storedPin) {
      console.warn(`Ambulance ${found.id} has a non-hashed PIN on file; login denied until PIN reset.`);
    }
    return { ok: false, invalidCredentials: true, pinUpgradeRequired: !!storedPin };
  }
  if (!pinMatches(storedPin, pinNorm)) {
    return { ok: false, invalidCredentials: true };
  }

  // Upgrade legacy unsalted SHA-256 hashes to PBKDF2 after successful verify.
  if (/^[a-f0-9]{64}$/i.test(String(storedPin || '').trim())) {
    try {
      await db
        .collection('ambulances')
        .doc(found.id)
        .collection('private')
        .doc('settings')
        .set({
          pin: hashAmbulancePin(pinNorm),
          pinUpdatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
    } catch (e) {
      console.warn(`Ambulance ${found.id} PIN upgrade failed:`, e.message);
    }
  }

  return {
    ok: true,
    driverId: found.id,
    data: found.data,
    username: found.username,
  };
}

function ambulanceBookerMatches(profile, broadcast) {
  if (!profile || !broadcast) return false;

  const bookerPatientId = String(broadcast.patientId || '');
  const profileId = String(profile.profileId || '');
  const role = String(profile.role || '');

  return (
    (role === 'patient' && bookerPatientId === profileId)
    || (role === 'doctor' && bookerPatientId === profileId)
  );
}

function broadcastAlreadyRated(broadcast) {
  const rating = broadcast.rating;
  if (rating == null) return false;
  const numericRating = Number(rating);
  if (Number.isNaN(numericRating)) return false;
  if (numericRating === -1) {
    throw new HttpsError('failed-precondition', 'Rating was skipped for this trip.');
  }
  if (numericRating > 0) {
    throw new HttpsError('already-exists', 'Already rated.');
  }
  return false;
}

/**
 * When a patient/doctor books an ambulance, one ambulance_requests doc is
 * created per online driver. Send a high-priority FCM push to that driver.
 */
exports.notifyAmbulanceDriverOnNewRequest = onDocumentCreated(
  { document: 'ambulance_requests/{requestId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    if (data.status !== 'pending') return;

    const driverId = data.driverId;
    if (!driverId) return;

    const db = getFirestore();
    const patientName = data.patientName || 'Patient';
    const pickup = data.pickupLocation || 'Pickup location pending';
    const broadcastId = data.broadcastId || '';

    await sendFcmIfTokenExists(db, {
      collection: 'ambulances',
      docId: driverId,
      title: 'New Ambulance Request',
      body: `${patientName} · ${pickup}`,
      data: {
        type: 'ambulance_request',
        broadcastId,
        requestId: event.params.requestId,
        patientName,
        pickupLocation: pickup,
      },
      androidChannelId: 'ambulance_requests',
      logLabel: `ambulance driver ${driverId}`,
      resolveToken: async (firestore) => resolveAmbulanceDriverToken(firestore, driverId),
    });
  },
);

/**
 * When a broadcast is claimed (pending → accepted), mark other drivers' pending
 * request copies as taken. Admin SDK bypasses client list rules on ambulance_requests.
 */
exports.markAmbulanceSiblingRequestsTakenOnAccept = onDocumentUpdated(
  { document: 'ambulance_broadcasts/{broadcastId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;

    const prevStatus = String(before.status || '');
    const nextStatus = String(after.status || '');
    if (prevStatus === nextStatus || nextStatus !== 'accepted') return;

    const broadcastId = event.params.broadcastId;
    const winnerId = String(after.acceptedDriverId || '');
    if (!winnerId) return;

    const winnerName = String(after.acceptedAmbulanceName || '');

    const db = getFirestore();
    const snapshot = await db
      .collection('ambulance_requests')
      .where('broadcastId', '==', broadcastId)
      .where('status', '==', 'pending')
      .get();

    if (snapshot.empty) return;

    const batch = db.batch();
    let writes = 0;
    for (const doc of snapshot.docs) {
      const driverId = String(doc.data().driverId || '');
      if (driverId === winnerId) continue;
      batch.update(doc.ref, {
        status: 'taken',
        acceptedDriverId: winnerId,
        acceptedAmbulanceName: winnerName,
      });
      writes += 1;
    }

    if (writes === 0) return;
    await batch.commit();
  },
);

/**
 * When a broadcast is cancelled, mark non-terminal request copies cancelled
 * (driver-initiated: winning driver's copy may be rejected). Admin SDK only.
 */
exports.markAmbulanceSiblingRequestsOnBroadcastCancelled = onDocumentUpdated(
  { document: 'ambulance_broadcasts/{broadcastId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;

    const prevStatus = String(before.status || '');
    const nextStatus = String(after.status || '');
    if (prevStatus === nextStatus || nextStatus !== 'cancelled') return;

    const broadcastId = event.params.broadcastId;
    const cancelledByRole = String(after.cancelledByRole || '');
    const acceptedDriverId = String(before.acceptedDriverId || '');

    const db = getFirestore();
    const snapshot = await db
      .collection('ambulance_requests')
      .where('broadcastId', '==', broadcastId)
      .get();

    if (snapshot.empty) return;

    const terminal = new Set(['cancelled', 'rejected', 'completed']);
    const batch = db.batch();
    let writes = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const status = String(data.status || '');
      if (terminal.has(status)) continue;

      const driverId = String(data.driverId || '');
      const nextRequestStatus =
        cancelledByRole === 'driver' && acceptedDriverId !== '' && driverId === acceptedDriverId
          ? 'rejected'
          : 'cancelled';

      batch.update(doc.ref, { status: nextRequestStatus });
      writes += 1;
    }

    if (writes === 0) return;
    await batch.commit();
  },
);

/**
 * Persist a cross-device in-app notification for the doctor when a patient books.
 */
exports.notifyDoctorOnAppointmentCreated = onDocumentCreated(
  { document: 'appointments/{appointmentId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const appointment = event.data?.data();
    if (!appointment) return;

    const payload = buildDoctorNewAppointmentNotification(
      appointment,
      event.params.appointmentId,
    );
    if (!payload) return;

    const db = getFirestore();
    const recipientUid = await resolveDoctorRecipientUid(db, payload.recipientProfileId);
    if (!recipientUid) return;

    try {
      await createInAppNotification(db, {
        ...payload,
        recipientUid,
      });
    } catch (err) {
      console.error(
        'In-app notification create failed for appointment',
        event.params.appointmentId,
        err,
      );
    }

    const appointmentId = payload.targetId || event.params.appointmentId;
    const patientName =
      String(appointment.patientName || 'Patient').trim() || 'Patient';

    await sendFcmIfTokenExists(db, {
      collection: 'doctors',
      docId: payload.recipientProfileId,
      title: payload.title,
      body: payload.body,
      data: {
        type: 'appointment_new',
        appointmentId,
        patientName,
        doctorTrigger: payload.doctorTrigger || 'newAppointmentBooked',
      },
      androidChannelId: 'doctor_appointments',
      logLabel: `doctor ${payload.recipientProfileId} appointment ${appointmentId}`,
    });
  },
);

/**
 * Notify receiving specialist when another doctor refers a patient to them.
 */
exports.notifyDoctorOnReferralCreated = onDocumentCreated(
  { document: 'referrals/{referralId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const referral = event.data?.data();
    if (!referral) return;

    const payload = buildDoctorReferralReceivedNotification(
      referral,
      event.params.referralId,
    );
    if (!payload) return;

    const db = getFirestore();
    const recipientUid = await resolveDoctorRecipientUid(db, payload.recipientProfileId);
    if (!recipientUid) return;

    try {
      await createInAppNotification(db, {
        ...payload,
        recipientUid,
      });
    } catch (err) {
      console.error(
        'In-app notification create failed for referral',
        event.params.referralId,
        err,
      );
    }

    await sendFcmIfTokenExists(db, {
      collection: 'doctors',
      docId: payload.recipientProfileId,
      title: payload.title,
      body: payload.body,
      data: {
        type: 'referral_received',
        referralId: payload.targetId || event.params.referralId,
        doctorTrigger: payload.doctorTrigger || 'patientReferredToMe',
      },
      androidChannelId: 'doctor_appointments',
      logLabel: `doctor ${payload.recipientProfileId} referral ${event.params.referralId}`,
    });
  },
);

/**
 * Notify patient when a doctor accepts or declines a pending appointment request.
 */
exports.notifyPatientOnAppointmentStatusChanged = onDocumentUpdated(
  { document: 'appointments/{appointmentId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (before.doctorStatus === after.doctorStatus) return;

    const db = getFirestore();
    const inAppPayload = buildPatientAppointmentStatusNotification(
      before,
      after,
      event.params.appointmentId,
    );
    if (!inAppPayload) return;

    const patientId = inAppPayload.recipientProfileId;
    await writeInAppNotification(db, 'appointment.status_updated', inAppPayload, {
      appointmentId: event.params.appointmentId,
      patientId,
      recipientProfileId: patientId,
    });

    const appointmentId = inAppPayload.targetId || event.params.appointmentId;
    const status = after.doctorStatus === 'confirmed' ? 'confirmed' : 'cancelled';

    await sendFcmIfTokenExists(db, {
      collection: 'patients',
      docId: patientId,
      title: inAppPayload.title,
      body: inAppPayload.body,
      data: {
        type: 'appointment_status_update',
        appointmentId,
        status,
        doctorName: after.doctorName || 'Doctor',
        patientTrigger: inAppPayload.patientTrigger,
      },
      androidChannelId: 'patient_appointments',
      logLabel: `patient ${patientId} appointment ${appointmentId}`,
    });
  },
);

/**
 * Notify patient when a lab accepts or declines their booking request.
 */
exports.notifyPatientOnLabBookingUpdate = onDocumentUpdated(
  { document: 'lab_bookings/{bookingId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (before.status === after.status) return;
    if (after.status !== 'confirmed' && after.status !== 'declined') return;
    if (before.status !== 'requested') return;

    const patientId = after.patientId;
    if (!patientId) return;

    const db = getFirestore();
    const inAppPayload = buildPatientLabBookingStatusNotification(
      after,
      event.params.bookingId,
    );
    await writeInAppNotification(
      db,
      'lab_booking.status_updated',
      inAppPayload,
      {
        bookingId: event.params.bookingId,
        patientId,
        recipientProfileId: inAppPayload?.recipientProfileId,
      },
    );

    const labName = after.partnerLab || 'Lab';
    const testName = after.testName || 'lab test';
    const accepted = after.status === 'confirmed';
    const title = accepted ? 'Lab booking accepted' : 'Lab booking declined';
    const body = accepted
      ? `${labName} confirmed your ${testName} booking.`
      : `${labName} could not accept your ${testName} booking.`;

    await sendFcmIfTokenExists(db, {
      collection: 'patients',
      docId: patientId,
      title,
      body,
      data: {
        type: 'lab_booking_update',
        bookingId: event.params.bookingId,
        status: after.status,
        labName,
        testName,
      },
      androidChannelId: 'patient_lab_bookings',
      logLabel: `patient ${patientId} lab booking`,
    });
  },
);

/**
 * Notify patient when a lab uploads and submits a report.
 */
exports.notifyPatientOnLabReportReady = onDocumentUpdated(
  { document: 'lab_bookings/{bookingId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const hadReport = Boolean(before.reportFileName || before.reportStorageUrl);
    const hasReport = Boolean(after.reportFileName || after.reportStorageUrl);
    if (!hasReport || hadReport) return;
    if (after.status !== 'completed') return;

    const patientId = after.patientId;
    if (!patientId) return;

    const db = getFirestore();
    const inAppPayload = buildPatientLabReportReadyNotification(
      after,
      event.params.bookingId,
    );
    await writeInAppNotification(
      db,
      'lab_booking.report_ready',
      inAppPayload,
      {
        bookingId: event.params.bookingId,
        patientId,
        recipientProfileId: inAppPayload?.recipientProfileId,
      },
    );

    const labName = after.partnerLab || 'Lab';
    const testName = after.testName || 'lab test';
    const title = 'Lab report ready';
    const body = `${labName} shared your ${testName} report.`;

    await sendFcmIfTokenExists(db, {
      collection: 'patients',
      docId: patientId,
      title,
      body,
      data: {
        type: 'lab_report_ready',
        bookingId: event.params.bookingId,
        status: after.status,
        labName,
        testName,
      },
      androidChannelId: 'patient_lab_bookings',
      logLabel: `patient ${patientId} lab report`,
    });
  },
);

/**
 * Notify patient when a doctor creates a lab order.
 */
exports.notifyPatientOnLabOrderCreated = onDocumentCreated(
  { document: 'lab_orders/{orderId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const order = event.data?.data();
    if (!order) return;

    const patientId = order.patientId;
    if (!patientId) return;

    const db = getFirestore();
    const inAppPayload = buildPatientLabOrderNotification(order, event.params.orderId);
    await writeInAppNotification(db, 'lab_order.created', inAppPayload, {
      orderId: event.params.orderId,
      patientId,
      recipientProfileId: inAppPayload?.recipientProfileId,
    });
  },
);

/**
 * Notify doctor on lab connection request / approval / rejection.
 */
exports.notifyDoctorOnLabConnectionChanged = onDocumentWritten(
  { document: 'lab_connections/{connectionId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;

    const db = getFirestore();
    const inAppPayload = buildDoctorLabConnectionNotification(
      before,
      after,
      event.params.connectionId,
    );
    await writeInAppNotification(db, 'lab_connection.changed', inAppPayload, {
      connectionId: event.params.connectionId,
      doctorId: after.doctorId,
      recipientProfileId: inAppPayload?.recipientProfileId,
    });
  },
);

/**
 * Notify doctor on pharmacy connection request / approval / rejection.
 */
exports.notifyDoctorOnPharmacyConnectionChanged = onDocumentWritten(
  { document: 'pharmacy_connections/{connectionId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;

    const db = getFirestore();
    const inAppPayload = buildDoctorPharmacyConnectionNotification(
      before,
      after,
      event.params.connectionId,
    );
    await writeInAppNotification(db, 'pharmacy_connection.changed', inAppPayload, {
      connectionId: event.params.connectionId,
      doctorId: after.doctorId,
      recipientProfileId: inAppPayload?.recipientProfileId,
    });
  },
);

/**
 * Notify patient when a prescription is sent to a pharmacy.
 */
exports.notifyPatientOnPharmacyDeliveryCreated = onDocumentCreated(
  { document: 'pharmacy_deliveries/{deliveryId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const delivery = event.data?.data();
    if (!delivery) return;

    const patientId = delivery.patientId;
    if (!patientId) return;

    const db = getFirestore();
    const inAppPayload = buildPatientPharmacyDeliveryCreatedNotification(
      delivery,
      event.params.deliveryId,
    );
    await writeInAppNotification(db, 'pharmacy_delivery.created', inAppPayload, {
      deliveryId: event.params.deliveryId,
      patientId,
      recipientProfileId: inAppPayload?.recipientProfileId,
    });
  },
);

/**
 * Notify doctor when a pharmacy views, marks OOS, or dispenses a delivery.
 */
exports.notifyDoctorOnPharmacyDeliveryUpdated = onDocumentUpdated(
  { document: 'pharmacy_deliveries/{deliveryId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const db = getFirestore();
    const payloads = buildDoctorPharmacyDeliveryUpdatedNotifications(
      before,
      after,
      event.params.deliveryId,
    );
    for (const payload of payloads) {
      await writeInAppNotification(db, 'pharmacy_delivery.updated', payload, {
        deliveryId: event.params.deliveryId,
        doctorId: after.doctorId,
        recipientProfileId: payload?.recipientProfileId,
      });
    }
  },
);

/**
 * Notify patient when medicines are dispensed or partially dispensed.
 */
exports.notifyPatientOnPharmacyDeliveryUpdated = onDocumentUpdated(
  { document: 'pharmacy_deliveries/{deliveryId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const db = getFirestore();
    const inAppPayload = buildPatientPharmacyDeliveryUpdatedNotification(
      before,
      after,
      event.params.deliveryId,
    );
    await writeInAppNotification(db, 'pharmacy_delivery.updated', inAppPayload, {
      deliveryId: event.params.deliveryId,
      patientId: after.patientId,
      recipientProfileId: inAppPayload?.recipientProfileId,
    });

    if (!inAppPayload) return;

    const prescriptionId = inAppPayload.targetId || event.params.deliveryId;
    const partial = after.status === 'partiallyDispensed';

    await sendFcmIfTokenExists(db, {
      collection: 'patients',
      docId: after.patientId,
      title: inAppPayload.title,
      body: inAppPayload.body,
      data: {
        type: 'pharmacy_delivery_update',
        prescriptionId,
        deliveryId: event.params.deliveryId,
        partial: partial ? 'true' : 'false',
        storeName: after.storeName || 'Pharmacy',
        patientTrigger: inAppPayload.patientTrigger,
      },
      androidChannelId: 'patient_pharmacy',
      logLabel: `patient ${after.patientId} pharmacy ${event.params.deliveryId}`,
    });
  },
);

/** Returns declarative validation rules for the client engine. */
exports.getValidationRules = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('getValidationRules', { category: 'api' }, async (request) => {
    requireAuth(request);
    return { rules: RULES, vitalThresholds: VITAL_THRESHOLDS, version: 1 };
  }),
);

/** Validates a single field server-side. */
exports.validateField = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('validateField', { category: 'api' }, async (request) => {
    requireAuth(request);
    const { rule, value, params } = request.data || {};
    const safeRule = requireKnownRule(rule, RULES);
    const safeParams = sanitizeRuleParams(params);
    const safeValue =
      value == null || typeof value === 'number' || typeof value === 'boolean'
        ? value
        : sanitizePlainText(String(value), { maxLength: 500 });
    const result = runRule(safeRule, safeValue, safeParams);
    return { error: result.error ?? null };
  }),
);

/** Validates multiple fields server-side. */
exports.validateFormFields = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('validateFormFields', { category: 'api' }, async (request) => {
    requireAuth(request);
    const { checks } = request.data || {};
    if (!Array.isArray(checks)) {
      throw new HttpsError('invalid-argument', 'checks must be an array');
    }
    if (checks.length > 40) {
      throw new HttpsError('invalid-argument', 'Too many validation checks.');
    }
    const sanitized = checks.map((c, i) => {
      if (!c || typeof c !== 'object') {
        throw new HttpsError('invalid-argument', `Invalid check at index ${i}.`);
      }
      return {
        rule: requireKnownRule(c.rule, RULES),
        value:
          c.value == null || typeof c.value === 'number' || typeof c.value === 'boolean'
            ? c.value
            : sanitizePlainText(String(c.value), { maxLength: 500 }),
        params: sanitizeRuleParams(c.params),
      };
    });
    return validateFields(sanitized);
  }),
);

/** Sends registration OTP (server-side storage; SMS optional). */
exports.sendUserRegistrationOtp = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK },
  withSecurityLogging('sendUserRegistrationOtp', async (request) => {
  try {
    console.info('[sendUserRegistrationOtp] request', {
      hasAppCheck: Boolean(request.app),
      appId: request.app?.appId || null,
      otpType: request.data?.otpType || 'registration',
      mobileLast4: String(request.data?.mobile || '').replace(/\D/g, '').slice(-4),
      platform: request.rawRequest?.headers?.['x-client-platform'] || 'unknown',
    });
    if (ENFORCE_OTP_APP_CHECK && !request.app) {
      logUnusualTraffic(request, { pattern: 'app_check_missing', detail: 'sendUserRegistrationOtp' });
    }
    const firestore = getFirestore();
    const otpType = String(request.data?.otpType || 'registration').trim();
    if (otpType === 'registration') {
      const mobile = request.data?.mobile || request.data?.email || request.data?.identifier;
      const role = String(request.data?.role || 'patient').trim();
      if (!isDemoMobileInput(mobile, role)) {
        await enforceAbuseLimit(firestore, request, 'signup', {
          identifier: mobile,
          message: 'Too many account creation attempts. Please try again later.',
        });
      }
    } else {
      await enforceAbuseLimit(firestore, request, 'api');
    }
    return await sendUserRegistrationOtp(firestore, request.data || {}, {
      clientIp: getCallableClientIp(request),
    });
  } catch (err) {
    console.error('sendUserRegistrationOtp failed', err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('internal', 'Could not send OTP. Please try again.');
  }
}),
);

/** Returns which module a mobile number is registered under (read-only). */
exports.lookupMobileRegistration = onCall(
  { region: 'asia-south1' },
  withSecurityLogging('lookupMobileRegistration', async (request) => {
    try {
      const firestore = getFirestore();
      await enforceAbuseLimit(firestore, request, 'api', {
        message: 'Too many requests. Please try again later.',
      });
      return await lookupMobileRegistration(firestore, request.data || {});
    } catch (err) {
      console.error('lookupMobileRegistration failed', err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not look up mobile number.');
    }
  }),
);

/** Verifies registration OTP. */
exports.verifyUserRegistrationOtp = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK },
  withSecurityLogging('verifyUserRegistrationOtp', async (request) => {
  try {
    const firestore = getFirestore();
    await enforceAbuseLimit(firestore, request, 'api', {
      message: 'Too many OTP verification attempts. Please try again later.',
    });
    return await verifyUserRegistrationOtp(
      firestore,
      request.data || {},
      request.auth,
      { clientIp: getCallableClientIp(request) },
    );
  } catch (err) {
    console.error('verifyUserRegistrationOtp failed', err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('internal', 'Could not verify OTP. Please try again.');
  }
}),
);
/** Applies a pre-registration OTP session to the signed-in patient account. */
exports.finalizePatientOtpVerification = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK },
  protectCallable('finalizePatientOtpVerification', { category: 'api' }, async (request) => {
    requireAuth(request);
    const firestore = getFirestore();
    return finalizePatientOtpVerification(firestore, request.data || {}, request.auth);
  }),
);

/** Resets ambulance driver PIN after OTP verification (Admin SDK write to private/settings). */
exports.resetAmbulanceDriverPin = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK },
  protectCallable('resetAmbulanceDriverPin', { category: 'login' }, async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Anonymous sign-in required.');
      }
      const firestore = getFirestore();
      return await resetAmbulanceDriverPin(firestore, request.data || {}, request.auth, {
        clientIp: getCallableClientIp(request),
      });
    } catch (err) {
      console.error('resetAmbulanceDriverPin failed', err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not reset PIN. Please try again.');
    }
  }),
);

/** Resets user password after OTP verification using Admin SDK. */
exports.resetUserPasswordWithOtp = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK },
  withSecurityLogging('resetUserPasswordWithOtp', async (request) => {
    try {
      const firestore = getFirestore();
      await enforceAbuseLimit(firestore, request, 'login', {
        identifier: request.data?.identifier || request.data?.mobile || request.data?.email,
        message: 'Too many password reset attempts. Please try again later.',
      });
      const result = await resetUserPasswordWithOtp(firestore, request.data || {}, {
        clientIp: getCallableClientIp(request),
      });
      logAuthAttempt(request, {
        outcome: 'success',
        method: 'password_reset',
        identifier: request.data?.identifier || request.data?.mobile || request.data?.email,
      });
      return result;
    } catch (err) {
      console.error('resetUserPasswordWithOtp failed', err);
      logAuthAttempt(request, {
        outcome: 'failure',
        method: 'password_reset',
        identifier: request.data?.identifier || request.data?.mobile || request.data?.email,
        reason: err?.code || 'error',
      });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not reset password. Please try again.');
    }
  }),
);

/** Exchanges a verified mobile OTP session for a Firebase custom auth token. */
exports.completeMobileOtpLogin = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_OTP_APP_CHECK },
  withSecurityLogging('completeMobileOtpLogin', async (request) => {
    try {
      const firestore = getFirestore();
      await enforceAbuseLimit(firestore, request, 'login', {
        identifier: request.data?.mobile || request.data?.identifier,
        message: 'Too many login attempts. Please try again later.',
      });
      const result = await completeMobileOtpLogin(firestore, request.data || {}, {
        clientIp: getCallableClientIp(request),
      });
      logAuthAttempt(request, {
        outcome: 'success',
        method: 'mobile_otp',
        identifier: request.data?.mobile || request.data?.identifier,
      });
      return result;
    } catch (err) {
      console.error('completeMobileOtpLogin failed', err);
      logAuthAttempt(request, {
        outcome: 'failure',
        method: 'mobile_otp',
        identifier: request.data?.mobile || request.data?.identifier,
        reason: err?.code || 'error',
      });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not complete OTP login. Please try again.');
    }
  }),
);

/** Pre-login rate-limit gate for email/password and admin sign-in. */
exports.assertLoginAllowed = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  withSecurityLogging('assertLoginAllowed', async (request) => {
  const firestore = getFirestore();
  await enforceAbuseLimit(firestore, request, 'login', {
    identifier: request.data?.identifier || request.data?.email,
    message: 'Too many login attempts. Please try again later.',
  });
  try {
    return await assertLoginAllowed(firestore, request.data || {}, {
      clientIp: getCallableClientIp(request),
    });
  } catch (err) {
    if (err?.code === 'resource-exhausted') {
      logAuthAttempt(request, {
        outcome: 'blocked',
        method: 'email_password',
        identifier: request.data?.identifier || request.data?.email,
        reason: 'rate_limited',
      });
    }
    throw err;
  }
}),
);

/** Records a failed email/password login for rate limiting. */
exports.recordFailedLogin = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('recordFailedLogin', { category: 'api' }, async (request) => {
  const firestore = getFirestore();
  logAuthAttempt(request, {
    outcome: 'failure',
    method: 'email_password',
    identifier: request.data?.identifier || request.data?.email,
    reason: 'invalid_credentials',
  });
  return recordFailedLogin(firestore, request.data || {}, {
    clientIp: getCallableClientIp(request),
  });
}),
);

/** Clears failed-login counters after a successful sign-in. */
exports.clearFailedLogins = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('clearFailedLogins', { category: 'api' }, async (request) => {
  const firestore = getFirestore();
  logAuthAttempt(request, {
    outcome: 'success',
    method: 'email_password',
    identifier: request.data?.identifier || request.data?.email,
  });
  return clearFailedLogins(firestore, request.data || {});
}),
);

/**
 * Returns a pending ambulance invite only when inviteId + token both match.
 * Replaces anonymous Firestore get-by-id (IDOR on timestamp invite IDs).
 */
exports.getAmbulanceInvite = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  withSecurityLogging('getAmbulanceInvite', async (request) => {
  assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
  await enforceAbuseLimit(getFirestore(), request, 'api');
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign-in required to open an invite.');
  }
  const inviteId = requireDocId(request.data?.inviteId, 'inviteId');
  const token = requireInviteToken(request.data?.token, 'token');

  const firestore = getFirestore();
  const snap = await firestore.collection('ambulance_invites').doc(inviteId).get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Invite not found.');
  }
  const data = snap.data() || {};
  if (String(data.token || '') !== token) {
    logUnusualTraffic(request, {
      pattern: 'forbidden_resource',
      detail: 'ambulance_invite_token_mismatch',
      identifier: inviteId,
    });
    throw new HttpsError('permission-denied', 'Invalid invite link.');
  }
  if (String(data.status || '') !== 'pending') {
    throw new HttpsError('failed-precondition', 'This invite has already been used.');
  }
  const expiresAt = data.expiresAt?.toDate?.();
  if (expiresAt && Date.now() > expiresAt.getTime()) {
    throw new HttpsError('deadline-exceeded', 'This invite link has expired.');
  }

  return { ok: true, inviteId: snap.id, invite: data };
}),
);

/** Developer/admin approval: sets role profile verified = true for any account role. */
exports.approveUserAccount = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('approveUserAccount', { category: 'api' }, async (request) => {
    requireAuth(request);
    const firestore = getFirestore();
    return approveUserAccount(firestore, request.data || {}, request.auth);
  }),
);

/** Backward-compatible alias for patient approval. */
exports.approvePatientAccount = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('approvePatientAccount', { category: 'api' }, async (request) => {
    requireAuth(request);
    const firestore = getFirestore();
    return approvePatientAccount(firestore, request.data || {}, request.auth);
  }),
);

/** Returns vitals advisory for prescription fields (treated as AI/advisory generation). */
exports.validateVitalAdvisory = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('validateVitalAdvisory', {
    category: 'ai',
    message: 'Too many AI advisory requests. Please wait and try again.',
  }, async (request) => {
    requireAuth(request);
    const { rule, value } = request.data || {};
    if (!rule || typeof rule !== 'string') {
      throw new HttpsError('invalid-argument', 'rule is required');
    }
    return runVitalAdvisory(rule, value);
  }),
);

/**
 * Explicit AI generation quota gate for future / existing generative features.
 * Client should call before any LLM / generative request.
 */
exports.consumeAiGenerationQuota = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('consumeAiGenerationQuota', {
    category: 'ai',
    message: 'AI generation rate limit exceeded. Please try again later.',
  }, async (request) => {
    requireAuth(request);
    return {
      ok: true,
      limits: {
        perHourPerUser: 40,
        perHourPerIp: 60,
      },
    };
  }),
);

/**
 * Account creation gate — call before Firebase createUserWithEmailAndPassword.
 */
exports.assertAccountCreationAllowed = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('assertAccountCreationAllowed', {
    category: 'signup',
    identifierFromRequest: (request) =>
      request.data?.email || request.data?.mobile || request.data?.identifier,
    message: 'Too many account creation attempts from this device or identity.',
  }, async (request) => {
    const emailRaw = String(request.data?.email || '').trim();
    const mobileRaw = String(request.data?.mobile || '').trim();
    if (!emailRaw && !mobileRaw) {
      throw new HttpsError('invalid-argument', 'email or mobile is required.');
    }
    if (emailRaw) requireEmail(emailRaw, 'email');
    if (mobileRaw) {
      const digits = mobileRaw.replace(/\D/g, '');
      let normalized = digits;
      if (normalized.length === 12 && normalized.startsWith('91')) normalized = normalized.slice(2);
      else if (normalized.length === 11 && normalized.startsWith('0')) normalized = normalized.slice(1);
      if (normalized.length !== 10 || !/^[6-9]\d{9}$/.test(normalized)) {
        throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile.');
      }
    }
    return { ok: true };
  }),
);

/**
 * Shared username/password verification for ambulance driver login.
 */
async function runVerifyAmbulanceDriverLogin(firestore, payload, { clientIp, requestForLimits }) {
  const username = requireUsername(payload?.username);
  const pin = requireAmbulancePassword(payload?.pin, 'password');

  await enforceAbuseLimit(firestore, requestForLimits, 'login', {
    identifier: `ambulance:${username}`,
    message: 'Too many login attempts. Please try again later.',
  });

  try {
    await assertLoginAllowed(firestore, { identifier: `ambulance:${username}` }, { clientIp });
  } catch (err) {
    logAuthAttempt(requestForLimits, {
      outcome: 'blocked',
      method: 'ambulance',
      identifier: username,
      reason: 'rate_limited',
    });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('resource-exhausted', 'Too many login attempts. Please try again later.');
  }

  const verified = await verifyAmbulanceCredentials(firestore, username, pin);
  if (!verified.ok) {
    await recordFailedLogin(firestore, { identifier: `ambulance:${username}` }, { clientIp }).catch(() => {});
    logAuthAttempt(requestForLimits, {
      outcome: 'failure',
      method: 'ambulance',
      identifier: username,
      reason: 'invalid_credentials',
    });
    return { ok: false, pinUpgradeRequired: verified.pinUpgradeRequired === true };
  }

  await clearFailedLogins(firestore, { identifier: `ambulance:${username}` }).catch(() => {});
  logAuthAttempt(requestForLimits, {
    outcome: 'success',
    method: 'ambulance',
    identifier: username,
  });

  const data = verified.data || {};
  return {
    ok: true,
    driverId: verified.driverId,
    serviceName: data.serviceName || '',
    driverName: data.driverName || '',
    username: data.username || verified.username,
    city: data.city || '',
    isAvailable: data.isAvailable !== false,
  };
}

/**
 * Verifies ambulance driver username/PIN server-side so PIN hashes are never
 * exposed to clients. Auth is optional here (PIN is verified server-side); the
 * client links an anonymous Firebase session after success for Firestore access.
 */
exports.verifyAmbulanceDriverLogin = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, invoker: 'public' },
  withSecurityLogging('verifyAmbulanceDriverLogin', async (request) => {
  try {
  const firestore = getFirestore();
  const clientIp = getCallableClientIp(request);
  return await runVerifyAmbulanceDriverLogin(
    firestore,
    request.data || {},
    { clientIp, requestForLimits: request },
  );
  } catch (err) {
    console.error('verifyAmbulanceDriverLogin failed', err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError(
      'internal',
      'Could not verify ambulance login. Please try again.',
    );
  }
}),
);

/**
 * Web-friendly HTTP entry (CORS enabled). Flutter web callables can send an empty
 * Authorization header; this endpoint accepts a proper Bearer token via fetch.
 */
exports.verifyAmbulanceDriverLoginHttp = onRequest(
  { region: CALLABLE_REGION, cors: true, invoker: 'public' },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: { status: 'INVALID_ARGUMENT', message: 'POST required.' } });
      return;
    }

    const clientIp = String(req.headers['x-forwarded-for'] || req.ip || 'unknown')
      .split(',')[0]
      .trim();
    const requestForLimits = { auth: null, rawRequest: req, app: null };

    try {
      const firestore = getFirestore();
      const payload = req.body?.data ?? req.body ?? {};
      const result = await runVerifyAmbulanceDriverLogin(
        firestore,
        payload,
        { clientIp, requestForLimits },
      );
      res.status(200).json({ result });
    } catch (err) {
      console.error('verifyAmbulanceDriverLoginHttp failed', err);
      if (err instanceof HttpsError) {
        const status = err.code === 'resource-exhausted' ? 429 : 400;
        res.status(status).json({
          error: {
            status: String(err.code || 'internal').toUpperCase(),
            message: err.message || 'Request failed.',
          },
        });
        return;
      }
      res.status(500).json({
        error: {
          status: 'INTERNAL',
          message: 'Could not verify ambulance login. Please try again.',
        },
      });
    }
  },
);

/** Ambulance driver login via verified mobile OTP session (anonymous auth required). */
exports.completeAmbulanceMobileOtpLogin = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, invoker: 'public' },
  withSecurityLogging('completeAmbulanceMobileOtpLogin', async (request) => {
    try {
      const firestore = getFirestore();
      return await completeAmbulanceMobileOtpLogin(
        firestore,
        request.data || {},
        request.auth,
        { clientIp: getCallableClientIp(request) },
      );
    } catch (err) {
      console.error('completeAmbulanceMobileOtpLogin failed', err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', 'Could not complete mobile login.');
    }
  }),
);

/**
 * Server-side ambulance trip rating. Validates booker + completed trip, prevents
 * duplicate ratings, and atomically updates ambulance rating aggregates.
 */
exports.submitAmbulanceRating = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('submitAmbulanceRating', { category: 'api' }, async (request) => {
  requireAuth(request);

  const broadcastId = requireDocId(request.data?.broadcastId, 'broadcastId');
  const ambulanceId = requireDocId(request.data?.ambulanceId, 'ambulanceId');
  const stars = requireStars(request.data?.stars);
  const review = sanitizeReview(request.data?.review || '');

  const db = getFirestore();
  const uid = request.auth.uid;

  const userSnap = await db.collection('users').doc(uid).get();
  if (!userSnap.exists) {
    throw new HttpsError('permission-denied', 'Unauthorized.');
  }
  const profile = userSnap.data() || {};

  const broadcastRef = db.collection('ambulance_broadcasts').doc(broadcastId);
  const ambRef = db.collection('ambulances').doc(ambulanceId);

  const broadcastSnap = await broadcastRef.get();
  if (!broadcastSnap.exists) {
    throw new HttpsError('not-found', 'Trip not found.');
  }

  const broadcast = broadcastSnap.data() || {};
  if (broadcast.status !== 'completed') {
    throw new HttpsError('failed-precondition', 'Trip not completed.');
  }
  if (String(broadcast.acceptedDriverId || '') !== ambulanceId) {
    throw new HttpsError('invalid-argument', 'Ambulance does not match this trip.');
  }
  if (!ambulanceBookerMatches(profile, broadcast)) {
    throw new HttpsError('permission-denied', 'Unauthorized.');
  }
  broadcastAlreadyRated(broadcast);

  const ratingFields = {
    rating: stars,
    ratedAt: FieldValue.serverTimestamp(),
  };
  if (review) {
    ratingFields.review = review;
  }

  await db.runTransaction(async (tx) => {
    const liveBroadcastSnap = await tx.get(broadcastRef);
    if (!liveBroadcastSnap.exists) {
      throw new HttpsError('not-found', 'Trip not found.');
    }

    const liveBroadcast = liveBroadcastSnap.data() || {};
    if (liveBroadcast.status !== 'completed') {
      throw new HttpsError('failed-precondition', 'Trip not completed.');
    }
    if (String(liveBroadcast.acceptedDriverId || '') !== ambulanceId) {
      throw new HttpsError('invalid-argument', 'Ambulance does not match this trip.');
    }
    if (!ambulanceBookerMatches(profile, liveBroadcast)) {
      throw new HttpsError('permission-denied', 'Unauthorized.');
    }
    broadcastAlreadyRated(liveBroadcast);

    const ambSnap = await tx.get(ambRef);
    if (!ambSnap.exists) {
      throw new HttpsError('not-found', 'Ambulance not found.');
    }

    const ambData = ambSnap.data() || {};
    const oldCount = Number(ambData.ratingCount) || 0;
    const oldTotal = Number(ambData.totalRating) || 0;

    tx.update(ambRef, {
      ratingCount: oldCount + 1,
      totalRating: oldTotal + stars,
    });
    tx.update(broadcastRef, ratingFields);
  });

  const requestsSnap = await db
    .collection('ambulance_requests')
    .where('broadcastId', '==', broadcastId)
    .get();

  if (!requestsSnap.empty) {
    const batch = db.batch();
    for (const doc of requestsSnap.docs) {
      batch.update(doc.ref, ratingFields);
    }
    await batch.commit();
  }

  return { ok: true };
}),
);

/**
 * Re-links a driver's authUid after reinstall/device change. Requires username+PIN
 * verification so stale authUid values can be reclaimed without opening hijack.
 */
exports.resyncAmbulanceAuthUid = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, invoker: 'public' },
  protectCallable('resyncAmbulanceAuthUid', {
    category: 'login',
    identifierFromRequest: (request) =>
      `ambulance:${String(request.data?.username || '').trim().toLowerCase()}`,
  }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Anonymous sign-in required.');
  }

  const username = requireUsername(request.data?.username);
  const pin = requireAmbulancePassword(request.data?.pin, 'password');

  const firestore = getFirestore();
  const verified = await verifyAmbulanceCredentials(firestore, username, pin);
  if (!verified.ok) {
    throw new HttpsError('permission-denied', 'Incorrect username or PIN.');
  }

  await firestore.collection('ambulances').doc(verified.driverId).set({
    authUid: request.auth.uid,
  }, { merge: true });

  const data = verified.data;
  return {
    ok: true,
    driverId: verified.driverId,
    serviceName: data.serviceName || '',
    driverName: data.driverName || '',
    username: data.username || verified.username,
    city: data.city || '',
    isAvailable: data.isAvailable !== false,
  };
}),
);

/** Recompute doctor rating aggregates when a review is created or updated. */
exports.aggregateDoctorRatingOnReviewWrite = onDocumentWritten(
  { document: 'reviews/{reviewId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const before = event.data?.before?.data() || null;
    const after = event.data?.after?.data() || null;
    const doctorId = String((after || before)?.doctorId || '').trim();
    if (!doctorId) return;

    const db = getFirestore();
    const doctorRef = db.collection('doctors').doc(doctorId);
    const reviewsSnap = await db.collection('reviews').where('doctorId', '==', doctorId).get();

    let total = 0;
    let count = 0;
    for (const doc of reviewsSnap.docs) {
      const rating = Number(doc.data()?.rating);
      if (Number.isNaN(rating)) continue;
      total += rating;
      count += 1;
    }
    const avg = count === 0 ? 0 : Number((total / count).toFixed(2));

    await doctorRef.set({
      rating: avg,
      reviewCount: count,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  },
);

/** @deprecated Prefer aggregateDoctorRatingOnReviewWrite — kept temporarily for deploy compatibility. */
exports.aggregateDoctorRatingOnReviewCreate = onDocumentCreated(
  { document: 'reviews/{reviewId}', region: FIRESTORE_TRIGGER_REGION },
  async () => {
    // No-op: full recompute handled by aggregateDoctorRatingOnReviewWrite.
  },
);

/** Keep helpfulCount in sync with vote subcollection writes. */
exports.syncReviewHelpfulCount = onDocumentWritten(
  { document: 'reviews/{reviewId}/votes/{voterId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    const reviewRef = event.data.after?.ref.parent.parent;
    if (!reviewRef) return;

    const db = getFirestore();
    const votesSnap = await reviewRef.collection('votes').count().get();
    const count = votesSnap.data().count || 0;
    await reviewRef.update({ helpfulCount: count });
  },
);

/**
 * One-time migration: grant careTeamDoctorIds from historical appointments.
 * Set BACKFILL_ADMIN_EMAILS env (comma-separated) on the function before calling.
 */
exports.backfillPatientCareTeams = onCall(
  { timeoutSeconds: 540, region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('backfillPatientCareTeams', { category: 'api' }, async (request) => {
  requireAuth(request);

  const allowedEmails = (process.env.BACKFILL_ADMIN_EMAILS || '')
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  const callerEmail = String(request.auth.token.email || '').trim().toLowerCase();
  // Fail closed: empty allow-list must not grant access to every authenticated user.
  if (allowedEmails.length === 0 || !allowedEmails.includes(callerEmail)) {
    throw new HttpsError('permission-denied', 'Not authorized to run migration.');
  }
  if (request.data?.confirm !== true) {
    throw new HttpsError('invalid-argument', 'Pass { confirm: true } to run migration.');
  }

  const db = getFirestore();
  let lastDoc = null;
  let scanned = 0;
  let updated = 0;
  const pending = new Map();

  while (true) {
    let query = db.collection('appointments').orderBy('__name__').limit(200);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      scanned += 1;
      const data = doc.data();
      const patientId = String(data.patientId || '').trim();
      const doctorId = String(data.doctorId || '').trim();
      if (!patientId || !doctorId) continue;
      if (!/^p\d+$|^wi/i.test(patientId)) continue;

      if (!pending.has(patientId)) pending.set(patientId, new Set());
      pending.get(patientId).add(doctorId);
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < 200) break;
  }

  for (const [patientId, doctorIds] of pending.entries()) {
    const patientRef = db.collection('patients').doc(patientId);
    const patientSnap = await patientRef.get();
    if (!patientSnap.exists) continue;

    await patientRef.set(
      {
        careTeamDoctorIds: FieldValue.arrayUnion(...doctorIds),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    updated += 1;
  }

  return { scanned, patientsUpdated: updated };
}),
);

exports.createRazorpayOrder = createRazorpayOrder;
exports.verifyRazorpayPayment = verifyRazorpayPayment;

const { sendMsg91Email } = require('./msg91_email');

/**
 * Triggered whenever an email is queued into the `mail` collection in Firestore.
 * Automatically dispatches the email via MSG91 Email API v5.
 */
exports.processMailQueueMsg91 = onDocumentCreated(
  {
    document: 'mail/{mailId}',
    region: FIRESTORE_TRIGGER_REGION,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    const to = Array.isArray(data.to) ? data.to[0] : (data.to || data.toEmail);
    if (!to) return;

    const templateId = data.templateId ||
      data.template_id ||
      (data.type === 'verification_approval' ? process.env.MSG91_TEMPLATE_ID_APPROVAL : null) ||
      (data.type === 'verification_rejection' ? process.env.MSG91_TEMPLATE_ID_REJECTION : null) ||
      process.env.MSG91_TEMPLATE_ID ||
      '';

    const message = data.message || {};
    const subject = message.subject || data.subject || 'DoctorNect Notification';
    const html = message.html || data.html || data.body || '';

    const variables = data.variables || {
      NAME: data.recipientName || 'User',
      ROLE: data.providerType || 'Provider',
      REASON: data.rejectionReason || data.reason || '',
    };

    const result = await sendMsg91Email({
      toEmail: to,
      recipientName: data.recipientName || 'User',
      templateId: templateId || undefined,
      subject: subject,
      html: html,
      variables: variables,
      fromEmail: data.fromEmail || process.env.MSG91_FROM_EMAIL || 'no-reply@mail.doctornect.com',
      domain: data.domain || process.env.MSG91_EMAIL_DOMAIN || 'mail.doctornect.com',
    });

    await snap.ref.set(
      {
        delivery: {
          state: result.success ? 'SUCCESS' : 'ERROR',
          attempts: 1,
          endTime: FieldValue.serverTimestamp(),
          error: result.error || null,
          msg91Response: result.data || null,
        },
      },
      { merge: true }
    );
  }
);

exports.sendMsg91EmailCallable = onCall(
  { ...MSG91_VPC_OPTIONS, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  protectCallable('sendMsg91EmailCallable', { category: 'api' }, async (request) => {
  requireAuth(request);
  const allowedEmails = (
    process.env.ACCOUNT_APPROVAL_ADMIN_EMAILS
    || process.env.BACKFILL_ADMIN_EMAILS
    || ''
  )
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  const callerEmail = String(request.auth.token.email || '').trim().toLowerCase();
  if (allowedEmails.length === 0 || !allowedEmails.includes(callerEmail)) {
    throw new HttpsError('permission-denied', 'Not authorized to send email.');
  }

  const toEmail = requireEmail(request.data?.toEmail, 'toEmail');
  const recipientName = sanitizePlainText(request.data?.recipientName || 'User', {
    maxLength: 80,
  });
  const templateId = request.data?.templateId
    ? requireString(request.data.templateId, 'templateId', {
        min: 2,
        max: 80,
        pattern: /^[A-Za-z0-9_\-]+$/,
      })
    : undefined;
  const subject = sanitizePlainText(request.data?.subject || 'DoctorNect', {
    maxLength: 120,
  });
  // Never accept raw HTML from clients — plain text only.
  const body = sanitizePlainText(request.data?.body || request.data?.html || '', {
    maxLength: 5000,
  });
  return await sendMsg91Email({
    toEmail,
    recipientName,
    templateId,
    subject,
    html: undefined,
    body,
    variables: undefined,
    fromEmail: process.env.MSG91_FROM_EMAIL || 'no-reply@mail.doctornect.com',
    domain: process.env.MSG91_EMAIL_DOMAIN || 'mail.doctornect.com',
  });
}),
);

