'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');

const MAX_PATIENTS_PER_SLOT = 3;
const FIRESTORE_TRIGGER_REGION = 'asia-south2';
const CALLABLE_REGION = 'asia-south1';

const { enforceAbuseLimit, assertAppCheck } = require('./abuse_rate_limit');
const { resolveCallerIdentity } = require('./caller_identity');

const ENFORCE_ABUSE_APP_CHECK = String(
  process.env.ENFORCE_ABUSE_APP_CHECK || process.env.ENFORCE_OTP_APP_CHECK || 'true',
).trim().toLowerCase() !== 'false';

const DEFAULT_DOCTOR_AVAILABILITY = {
  workingDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
  morningStart: '09:00 AM',
  morningEnd: '01:00 PM',
  eveningEnabled: true,
  eveningStart: '04:00 PM',
  eveningEnd: '08:00 PM',
  slotDurationMins: 15,
  maxPatientsPerDay: 20,
  breakEnabled: false,
  breakStart: '01:00 PM',
  breakEnd: '02:00 PM',
  blockedDates: [],
};

/**
 * Converts a Date, Timestamp, ISO string, or epoch ms to Asia/Kolkata date (YYYY-MM-DD)
 * and 24-hour time (HH:mm). Handles day boundaries cleanly.
 */
function toIstDateAndTime(input) {
  let date;
  if (!input) {
    throw new Error('Missing dateTime');
  }
  if (typeof input.toDate === 'function') {
    date = input.toDate();
  } else if (input instanceof Date) {
    date = input;
  } else if (typeof input === 'number') {
    date = new Date(input);
  } else if (typeof input === 'string') {
    date = new Date(input);
  } else if (input._seconds !== undefined) {
    date = new Date(input._seconds * 1000);
  } else if (input.seconds !== undefined) {
    date = new Date(input.seconds * 1000);
  } else {
    date = new Date(input);
  }

  if (isNaN(date.getTime())) {
    throw new Error(`Invalid dateTime: ${JSON.stringify(input)}`);
  }

  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  });

  const parts = formatter.formatToParts(date);
  let year = '';
  let month = '';
  let day = '';
  let hour = '';
  let minute = '';
  for (const part of parts) {
    if (part.type === 'year') year = part.value;
    else if (part.type === 'month') month = part.value;
    else if (part.type === 'day') day = part.value;
    else if (part.type === 'hour') hour = part.value;
    else if (part.type === 'minute') minute = part.value;
  }

  const dateStr = `${year}-${month}-${day}`;
  const timeStr = `${hour}:${minute}`;
  return { date: dateStr, time: timeStr, year, month, day, hour, minute, dateObj: date };
}

/**
 * Derives the deterministic slot document ID: doctorId + Asia/Kolkata YYYY-MM-DD + HH:mm (24h).
 * Does NOT use the client slotLabel.
 */
function deriveSlotId(doctorId, dateTime) {
  const cleanDoctorId = String(doctorId || '').trim();
  if (!cleanDoctorId) {
    throw new Error('Missing doctorId');
  }
  const { date, time } = toIstDateAndTime(dateTime);
  return `${cleanDoctorId}_${date}_${time}`;
}

/**
 * Parses either 12-hour (e.g. "09:00 AM", "01:30 PM") or 24-hour (e.g. "09:00", "13:30")
 * time strings to minutes from midnight.
 */
function parseTimeToMinutes(timeStr) {
  if (!timeStr) return null;
  const str = String(timeStr).trim();
  const match12 = str.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  if (match12) {
    let hour = parseInt(match12[1], 10);
    const minute = parseInt(match12[2], 10);
    const meridiem = match12[3].toUpperCase();
    if (meridiem === 'AM' && hour === 12) hour = 0;
    if (meridiem === 'PM' && hour !== 12) hour += 12;
    return hour * 60 + minute;
  }
  const match24 = str.match(/^(\d{1,2}):(\d{2})$/);
  if (match24) {
    const hour = parseInt(match24[1], 10);
    const minute = parseInt(match24[2], 10);
    return hour * 60 + minute;
  }
  return null;
}

/**
 * Validates whether a given ISO/Timestamp dateTime falls inside a doctor's schedule.
 */
function isSlotInsideDoctorAvailability(availability, dateTime) {
  const { date, time, dateObj } = toIstDateAndTime(dateTime);
  const schedule = availability || DEFAULT_DOCTOR_AVAILABILITY;

  const istWeekday = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Kolkata',
    weekday: 'short',
  }).format(dateObj);

  const workingDays = Array.isArray(schedule.workingDays) && schedule.workingDays.length > 0
    ? schedule.workingDays
    : DEFAULT_DOCTOR_AVAILABILITY.workingDays;

  if (!workingDays.includes(istWeekday)) {
    return { valid: false, reason: `Doctor is not available on ${istWeekday} (weekly off).` };
  }

  if (Array.isArray(schedule.blockedDates)) {
    for (const b of schedule.blockedDates) {
      if (!b) continue;
      const bIst = toIstDateAndTime(b);
      if (bIst.date === date) {
        return { valid: false, reason: 'Doctor is on holiday on this date.' };
      }
    }
  }

  if (schedule.leaveStart && schedule.leaveEnd) {
    const startIst = toIstDateAndTime(schedule.leaveStart).date;
    const endIst = toIstDateAndTime(schedule.leaveEnd).date;
    if (date >= startIst && date <= endIst) {
      return { valid: false, reason: 'Doctor is on leave on this date.' };
    }
  }

  const slotMinutes = parseTimeToMinutes(time);
  if (slotMinutes == null) {
    return { valid: false, reason: 'Invalid slot time format.' };
  }

  const durationMins = Number(schedule.slotDurationMins) || 15;
  const slotEndMinutes = slotMinutes + durationMins;

  if (schedule.breakEnabled) {
    const breakStart = parseTimeToMinutes(schedule.breakStart);
    const breakEnd = parseTimeToMinutes(schedule.breakEnd);
    if (breakStart != null && breakEnd != null) {
      if (slotMinutes < breakEnd && slotEndMinutes > breakStart) {
        return { valid: false, reason: 'Doctor is on break during this time slot.' };
      }
    }
  }

  const morningStart = parseTimeToMinutes(schedule.morningStart || '09:00 AM');
  const morningEnd = parseTimeToMinutes(schedule.morningEnd || '01:00 PM');
  const inMorning = morningStart != null && morningEnd != null
    && slotMinutes >= morningStart && slotEndMinutes <= morningEnd;

  let inEvening = false;
  if (schedule.eveningEnabled !== false) {
    const eveningStart = parseTimeToMinutes(schedule.eveningStart || '04:00 PM');
    const eveningEnd = parseTimeToMinutes(schedule.eveningEnd || '08:00 PM');
    inEvening = eveningStart != null && eveningEnd != null
      && slotMinutes >= eveningStart && slotEndMinutes <= eveningEnd;
  }

  if (!inMorning && !inEvening) {
    return { valid: false, reason: 'Selected time slot is outside doctor working hours.' };
  }

  return { valid: true };
}

/**
 * Builds appointment document fields matching AppointmentFirestoreMapper.toMap.
 */
function buildAppointmentData({
  appointmentId,
  doctorId,
  doctorData,
  patientId,
  callerData,
  data,
  dateTimeTimestamp,
  tokenNumber = 1,
}) {
  const patientName = String(data?.patientName || callerData?.name || '').trim();
  const patientAge = Number(data?.patientAge) || Number(callerData?.age) || 0;
  const patientGender = String(data?.patientGender || callerData?.gender || 'Male').trim();
  const doctorName = String(doctorData?.name || doctorData?.doctorName || data?.doctorName || '').trim();
  const specialization = String(doctorData?.specialization || data?.specialization || '').trim();
  const slotLabel = String(data?.slotLabel || '').trim();
  const visitType = String(data?.visitType || 'newVisit').trim();
  const patientStatus = String(data?.patientStatus || 'pending').trim();
  const doctorStatus = String(data?.doctorStatus || 'pendingRequest').trim();

  const appointment = {
    appointmentId,
    doctorId,
    doctorName,
    specialization,
    patientId,
    patientName,
    patientAge,
    patientGender,
    dateTime: dateTimeTimestamp,
    slotLabel,
    tokenNumber: Number(tokenNumber) || 1,
    visitType,
    patientStatus,
    doctorStatus,
    hasPrescription: false,
    hasReport: false,
    hasReview: false,
    labReports: Array.isArray(data?.labReports) ? data.labReports : [],
    chiefComplaints: Array.isArray(data?.chiefComplaints)
      ? data.chiefComplaints
      : (data?.reasonForVisit ? [String(data.reasonForVisit).trim()] : []),
    symptoms: Array.isArray(data?.symptoms) ? data.symptoms : [],
    observations: Array.isArray(data?.observations) ? data.observations : [],
    wasRescheduled: false, // In bookAppointment, always false (reschedule will be a separate callable)
    // Server-set. data.createdVia is never copied onto the document.
    createdVia: 'bookAppointment',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (doctorData?.clinicName || data?.clinicName) {
    appointment.clinicName = data?.clinicName || doctorData?.clinicName;
  }
  if (doctorData?.clinicAddress || data?.clinicAddress) {
    appointment.clinicAddress = data?.clinicAddress || doctorData?.clinicAddress;
  }
  if (doctorData?.mapsUrl || data?.mapsUrl) {
    appointment.mapsUrl = data?.mapsUrl || doctorData?.mapsUrl;
  }
  if (data?.contactNumber || callerData?.mobile) {
    appointment.contactNumber = data?.contactNumber || callerData?.mobile;
  }
  if (data?.clinicalNotes) {
    appointment.clinicalNotes = data.clinicalNotes;
  }
  if (data?.source) {
    appointment.source = data.source;
  }
  if (data?.bookedByName) {
    appointment.bookedByName = data.bookedByName;
  }
  if (data?.patientRelation) {
    appointment.patientRelation = data.patientRelation;
  }
  if (data?.slotShareReason) {
    appointment.slotShareReason = data.slotShareReason;
  }

  return appointment;
}

/**
 * Reconciles doctor_slots within a Firestore transaction.
 * Idempotent: duplicate event delivery leaves arrays unchanged.
 * If legacy direct write pushes activeAppointmentIds.length > MAX_PATIENTS_PER_SLOT,
 * sets slotOverflow: true and logs it, never deleting anything.
 */
async function reconcileAppointmentSlotTransaction(db, {
  appointmentId,
  beforeActive,
  beforeDoctorId,
  beforeDateTime,
  afterActive,
  afterDoctorId,
  afterDateTime,
  afterTokenNumber = 0,
}) {
  const beforeSlotId = beforeActive && beforeDoctorId && beforeDateTime
    ? deriveSlotId(beforeDoctorId, beforeDateTime)
    : null;
  const afterSlotId = afterActive && afterDoctorId && afterDateTime
    ? deriveSlotId(afterDoctorId, afterDateTime)
    : null;

  if (!beforeSlotId && !afterSlotId) {
    return { reconciled: false, reason: 'neither_active' };
  }

  await db.runTransaction(async (tx) => {
    let beforeSnap = null;
    let afterSnap = null;

    if (beforeSlotId && beforeSlotId !== afterSlotId) {
      beforeSnap = await tx.get(db.collection('doctor_slots').doc(beforeSlotId));
    }
    if (afterSlotId) {
      afterSnap = await tx.get(db.collection('doctor_slots').doc(afterSlotId));
    }

    // On appointment CREATE or legacy write, raise doctor_day_counters to max(counter, tokenNumber)
    if (afterActive && afterDoctorId && afterDateTime && afterTokenNumber > 0) {
      const { date: afterDate } = toIstDateAndTime(afterDateTime);
      const dayCounterRef = db.collection('doctor_day_counters').doc(`${afterDoctorId}_${afterDate}`);
      const counterSnap = await tx.get(dayCounterRef);
      const currentLast = counterSnap.exists ? Number(counterSnap.data()?.lastTokenNumber || 0) : 0;
      if (afterTokenNumber > currentLast) {
        tx.set(
          dayCounterRef,
          {
            doctorId: afterDoctorId,
            date: afterDate,
            lastTokenNumber: afterTokenNumber,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    }

    // 1. Remove from before slot if cancelled, deleted, or rescheduled
    if (beforeSlotId && beforeSlotId !== afterSlotId && beforeSnap && beforeSnap.exists) {
      const beforeRef = db.collection('doctor_slots').doc(beforeSlotId);
      const currentBefore = beforeSnap.data()?.activeAppointmentIds || [];
      const updatedBefore = currentBefore.filter((id) => id !== appointmentId);
      const isOverflow = updatedBefore.length > MAX_PATIENTS_PER_SLOT;

      tx.set(
        beforeRef,
        {
          activeAppointmentIds: FieldValue.arrayRemove(appointmentId),
          updatedAt: FieldValue.serverTimestamp(),
          slotOverflow: isOverflow,
        },
        { merge: true },
      );
    }

    // 2. Add to after slot if created, uncancelled, or rescheduled
    if (afterSlotId) {
      const afterRef = db.collection('doctor_slots').doc(afterSlotId);
      const currentAfter = afterSnap && afterSnap.exists
        ? (afterSnap.data()?.activeAppointmentIds || [])
        : [];

      const alreadyPresent = currentAfter.includes(appointmentId);
      const newCount = alreadyPresent ? currentAfter.length : currentAfter.length + 1;
      const isOverflow = newCount > MAX_PATIENTS_PER_SLOT;

      if (isOverflow && !alreadyPresent) {
        console.warn(
          `[reconcileSlot] Slot ${afterSlotId} overflowed (${newCount} > ${MAX_PATIENTS_PER_SLOT}) due to appointment ${appointmentId}`
        );
      }

      const { date, time } = toIstDateAndTime(afterDateTime);
      tx.set(
        afterRef,
        {
          doctorId: afterDoctorId,
          date,
          time,
          activeAppointmentIds: FieldValue.arrayUnion(appointmentId),
          updatedAt: FieldValue.serverTimestamp(),
          slotOverflow: isOverflow,
        },
        { merge: true },
      );
    }
  });

  return { reconciled: true, beforeSlotId, afterSlotId };
}

function areDateTimesEqual(a, b) {
  if (a === b) return true;
  if (!a || !b) return false;
  const timeA = typeof a.toMillis === 'function' ? a.toMillis()
    : a instanceof Date ? a.getTime()
    : typeof a === 'number' ? a
    : typeof a._seconds === 'number' ? a._seconds * 1000 + Math.floor((a._nanoseconds || 0) / 1e6)
    : new Date(a).getTime();
  const timeB = typeof b.toMillis === 'function' ? b.toMillis()
    : b instanceof Date ? b.getTime()
    : typeof b === 'number' ? b
    : typeof b._seconds === 'number' ? b._seconds * 1000 + Math.floor((b._nanoseconds || 0) / 1e6)
    : new Date(b).getTime();
  return !isNaN(timeA) && !isNaN(timeB) && timeA === timeB;
}

/**
 * Handler for the appointments/{appointmentId} Firestore trigger.
 */
async function reconcileAppointmentSlotHandler(event, db = getFirestore(), handlerOptions = {}) {
  const { isDoctorPatientSupabasePrimary } = require('./sync_flags');
  const forceLegacy =
    handlerOptions.forceLegacy === true || event?.__testOptions?.forceLegacyReconcile === true;
  const isCutover = forceLegacy ? false : await isDoctorPatientSupabasePrimary();
  if (isCutover) {
    return { reconciled: false, reason: 'cutover_supabase_primary' };
  }
  const before = event.data?.before?.data() || null;
  const after = event.data?.after?.data() || null;
  const appointmentId = event.params?.appointmentId || event.data?.after?.id || event.data?.before?.id;

  if (!appointmentId) return;

  if (after && (!after.doctorId || !after.dateTime)) {
    console.warn(`[reconcileAppointmentSlot] Skipping malformed appointment ${appointmentId}: missing doctorId or dateTime`);
  }

  // Early return if neither doctorId, dateTime, cancellationReason, nor tokenNumber changed
  // (e.g. status, clinical notes, symptoms, or prescription updates do not cause slot reads or writes)
  if (before && after) {
    const doctorUnchanged = String(before.doctorId || '').trim() === String(after.doctorId || '').trim();
    const cancelUnchanged = Boolean(before.cancellationReason) === Boolean(after.cancellationReason);
    const dateTimeUnchanged = areDateTimesEqual(before.dateTime, after.dateTime);
    const tokenUnchanged = Number(before.tokenNumber || 0) === Number(after.tokenNumber || 0);

    if (doctorUnchanged && cancelUnchanged && dateTimeUnchanged && tokenUnchanged) {
      return { reconciled: false, reason: 'no_slot_relevant_changes' };
    }
  }

  const beforeActive = Boolean(before && before.doctorId && before.dateTime && !before.cancellationReason);
  const afterActive = Boolean(after && after.doctorId && after.dateTime && !after.cancellationReason);
  const afterTokenNumber = Number(after?.tokenNumber || 0);

  return await reconcileAppointmentSlotTransaction(db, {
    appointmentId,
    beforeActive,
    beforeDoctorId: before?.doctorId,
    beforeDateTime: before?.dateTime,
    afterActive,
    afterDoctorId: after?.doctorId,
    afterDateTime: after?.dateTime,
    afterTokenNumber,
  });
}

function parseAppointmentDateTime(dateTimeRaw) {
  if (!dateTimeRaw) {
    throw new HttpsError('invalid-argument', 'dateTime is required.');
  }
  if (typeof dateTimeRaw.toDate === 'function') return dateTimeRaw;
  if (dateTimeRaw instanceof Date) return Timestamp.fromDate(dateTimeRaw);
  if (typeof dateTimeRaw === 'string' || typeof dateTimeRaw === 'number') {
    return Timestamp.fromDate(new Date(dateTimeRaw));
  }
  if (dateTimeRaw._seconds !== undefined) {
    return new Timestamp(dateTimeRaw._seconds, dateTimeRaw._nanoseconds || 0);
  }
  if (dateTimeRaw.seconds !== undefined) {
    return new Timestamp(dateTimeRaw.seconds, dateTimeRaw.nanoseconds || 0);
  }
  throw new HttpsError('invalid-argument', 'Invalid dateTime format.');
}

async function allocateNextDayToken(tx, db, doctorId, slotDate) {
  const dayCounterRef = db.collection('doctor_day_counters').doc(`${doctorId}_${slotDate}`);
  const counterSnap = await tx.get(dayCounterRef);
  const lastToken = counterSnap.exists ? Number(counterSnap.data()?.lastTokenNumber || 0) : 0;
  const assignedTokenNumber = lastToken + 1;
  tx.set(
    dayCounterRef,
    {
      doctorId,
      date: slotDate,
      lastTokenNumber: assignedTokenNumber,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return assignedTokenNumber;
}

const RESCHEDULE_ALLOWED_STATUSES = new Set(['pendingRequest', 'confirmed', 'waiting']);

/**
 * Handler for the callable bookAppointment.
 */
async function bookAppointmentHandler(data, auth, db = getFirestore()) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to book an appointment.');
  }

  // 1. Verify caller is a patient (Supabase `users` when cutover is primary)
  let callerData;
  try {
    callerData = await resolveCallerIdentity({ db, uid: auth.uid });
  } catch (err) {
    if (err instanceof HttpsError && err.code === 'unauthenticated') {
      throw new HttpsError('permission-denied', 'User profile not found.');
    }
    throw err;
  }
  if (callerData.role !== 'patient') {
    throw new HttpsError('permission-denied', 'Only patients can book appointments.');
  }
  const patientId = String(
    callerData.profileId || callerData.profile_id || auth.uid,
  ).trim();

  // 2. Verify doctor exists, verified and not deactivated
  const doctorId = String(data?.doctorId || '').trim();
  if (!doctorId) {
    throw new HttpsError('invalid-argument', 'doctorId is required.');
  }

  const doctorSnap = await db.collection('doctors').doc(doctorId).get();
  if (!doctorSnap.exists) {
    throw new HttpsError('not-found', 'Doctor not found.');
  }
  const doctorData = doctorSnap.data() || {};
  if (doctorData.verified !== true) {
    throw new HttpsError('failed-precondition', 'Doctor is not verified.');
  }
  if (doctorData.deactivated === true) {
    throw new HttpsError('failed-precondition', 'Doctor account is deactivated.');
  }

  // 3. Verify slot inside doctor availability
  const dateTimeTimestamp = parseAppointmentDateTime(data?.dateTime);

  const availSnap = await db.collection('doctor_availability').doc(doctorId).get();
  const schedule = availSnap.exists ? availSnap.data() : DEFAULT_DOCTOR_AVAILABILITY;

  const availabilityCheck = isSlotInsideDoctorAvailability(schedule, dateTimeTimestamp);
  if (!availabilityCheck.valid) {
    throw new HttpsError('failed-precondition', availabilityCheck.reason);
  }

  // 4. Derive slot ID (doctorId + Asia/Kolkata YYYY-MM-DD + HH:mm)
  const slotId = deriveSlotId(doctorId, dateTimeTimestamp);
  const { date: slotDate, time: slotTime } = toIstDateAndTime(dateTimeTimestamp);

  const slotRef = db.collection('doctor_slots').doc(slotId);
  const apptRef = db.collection('appointments').doc();
  const appointmentId = apptRef.id;
  let assignedTokenNumber = 1;

  // 5. In ONE transaction: check capacity, check patient double-booking, check slotShareReason, increment day counter, create appointment, add to slot
  await db.runTransaction(async (tx) => {
    const slotSnap = await tx.get(slotRef);
    const slotData = slotSnap.exists ? slotSnap.data() : null;
    const currentActiveIds = slotData?.activeAppointmentIds || [];

    // Capacity check
    if (currentActiveIds.length >= MAX_PATIENTS_PER_SLOT) {
      throw new HttpsError(
        'resource-exhausted',
        `This time slot is full. Maximum ${MAX_PATIENTS_PER_SLOT} patients allowed at the same time.`
      );
    }

    // Check if patient already has active appointment in that slot
    for (const existingId of currentActiveIds) {
      const existingApptSnap = await tx.get(db.collection('appointments').doc(existingId));
      if (existingApptSnap.exists) {
        const existingData = existingApptSnap.data() || {};
        const existingName = String(existingData.patientName || '').trim().toLowerCase();
        const incomingName = String(data?.patientName || callerData?.name || '').trim().toLowerCase();
        const samePerson = incomingName.length === 0 || existingName === incomingName;
        // Same account may book a different family member in this slot.
        // The max-3 cap and slotShareReason checks below still apply.
        if (existingData.patientId === patientId && !existingData.cancellationReason && samePerson) {
          throw new HttpsError(
            'failed-precondition',
            'You already have an active appointment in this time slot.'
          );
        }
      }
    }

    // Require slotShareReason if slot already has 1 or 2 active bookings (matching UI rule)
    // Client-supplied wasRescheduled is NOT honored in bookAppointment; always treated as false.
    if (currentActiveIds.length >= 1) {
      const slotShareReason = String(data?.slotShareReason || '').trim();
      if (!slotShareReason) {
        throw new HttpsError(
          'invalid-argument',
          'Please provide a reason for sharing this time slot.',
        );
      }
    }

    assignedTokenNumber = await allocateNextDayToken(tx, db, doctorId, slotDate);

    // Build appointment matching AppointmentFirestoreMapper
    const appointmentDoc = buildAppointmentData({
      appointmentId,
      doctorId,
      doctorData,
      patientId,
      callerData,
      data,
      dateTimeTimestamp,
      tokenNumber: assignedTokenNumber,
    });

    tx.set(apptRef, appointmentDoc);

    const newActiveIds = [...currentActiveIds, appointmentId];
    tx.set(
      slotRef,
      {
        doctorId,
        date: slotDate,
        time: slotTime,
        activeAppointmentIds: FieldValue.arrayUnion(appointmentId),
        updatedAt: FieldValue.serverTimestamp(),
        slotOverflow: newActiveIds.length > MAX_PATIENTS_PER_SLOT,
      },
      { merge: true },
    );
  });

  return {
    ok: true,
    appointmentId,
    slotId,
    doctorId,
    patientId,
    slotDate,
    slotTime,
    tokenNumber: assignedTokenNumber,
  };
}

/**
 * Cloud Function Trigger on appointments/{appointmentId} in asia-south2.
 */
const reconcileAppointmentSlot = onDocumentWritten(
  { document: 'appointments/{appointmentId}', region: FIRESTORE_TRIGGER_REGION },
  async (event) => {
    try {
      await reconcileAppointmentSlotHandler(event);
    } catch (err) {
      console.error('[reconcileAppointmentSlot] Error reconciling slot:', err);
    }
  },
);

/**
 * Patient reschedule. Allocates a new day token only when the IST day changes.
 * Client-sent tokenNumber, patientId, doctorId, and createdVia are ignored.
 */
async function rescheduleAppointmentHandler(data, auth, db = getFirestore()) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to reschedule an appointment.');
  }

  const callerSnap = await db.collection('users').doc(auth.uid).get();
  if (!callerSnap.exists) {
    throw new HttpsError('permission-denied', 'User profile not found.');
  }
  const callerData = callerSnap.data() || {};
  if (callerData.role !== 'patient') {
    throw new HttpsError('permission-denied', 'Only patients can reschedule appointments.');
  }
  const callerPatientId = String(callerData.profileId || auth.uid).trim();

  const appointmentId = String(data?.appointmentId || '').trim();
  if (!appointmentId) {
    throw new HttpsError('invalid-argument', 'appointmentId is required.');
  }
  const slotLabel = String(data?.slotLabel || '').trim();
  if (!slotLabel) {
    throw new HttpsError('invalid-argument', 'slotLabel is required.');
  }

  const dateTimeTimestamp = parseAppointmentDateTime(data?.dateTime);
  const apptRef = db.collection('appointments').doc(appointmentId);
  const existingSnap = await apptRef.get();
  if (!existingSnap.exists) {
    throw new HttpsError('not-found', 'Appointment not found.');
  }
  const existing = existingSnap.data() || {};
  if (String(existing.patientId || '').trim() !== callerPatientId) {
    throw new HttpsError('permission-denied', 'You can only reschedule your own appointment.');
  }
  const doctorStatus = String(existing.doctorStatus || '').trim();
  if (!RESCHEDULE_ALLOWED_STATUSES.has(doctorStatus)) {
    throw new HttpsError(
      'failed-precondition',
      'This appointment cannot be rescheduled.',
    );
  }

  const doctorId = String(existing.doctorId || '').trim();
  const doctorSnap = await db.collection('doctors').doc(doctorId).get();
  if (!doctorSnap.exists) {
    throw new HttpsError('not-found', 'Doctor not found.');
  }
  const doctorData = doctorSnap.data() || {};
  if (doctorData.verified !== true) {
    throw new HttpsError('failed-precondition', 'Doctor is not verified.');
  }
  if (doctorData.deactivated === true) {
    throw new HttpsError('failed-precondition', 'Doctor account is deactivated.');
  }

  const availSnap = await db.collection('doctor_availability').doc(doctorId).get();
  const schedule = availSnap.exists ? availSnap.data() : DEFAULT_DOCTOR_AVAILABILITY;
  const availabilityCheck = isSlotInsideDoctorAvailability(schedule, dateTimeTimestamp);
  if (!availabilityCheck.valid) {
    throw new HttpsError('failed-precondition', availabilityCheck.reason);
  }

  const newSlotId = deriveSlotId(doctorId, dateTimeTimestamp);
  const { date: newDate, time: newTime } = toIstDateAndTime(dateTimeTimestamp);
  const oldIst = toIstDateAndTime(existing.dateTime);
  const sameDay = oldIst.date === newDate;
  let tokenNumber = Number(existing.tokenNumber || 0);

  await db.runTransaction(async (tx) => {
    const freshSnap = await tx.get(apptRef);
    if (!freshSnap.exists) {
      throw new HttpsError('not-found', 'Appointment not found.');
    }
    const fresh = freshSnap.data() || {};
    if (String(fresh.patientId || '').trim() !== callerPatientId) {
      throw new HttpsError('permission-denied', 'You can only reschedule your own appointment.');
    }
    const freshStatus = String(fresh.doctorStatus || '').trim();
    if (!RESCHEDULE_ALLOWED_STATUSES.has(freshStatus)) {
      throw new HttpsError(
        'failed-precondition',
        'This appointment cannot be rescheduled.',
      );
    }

    const oldSlotId = deriveSlotId(doctorId, fresh.dateTime);
    if (sameDay) {
      tokenNumber = Number(fresh.tokenNumber || 0);
    } else {
      tokenNumber = await allocateNextDayToken(tx, db, doctorId, newDate);
    }

    if (oldSlotId !== newSlotId) {
      const newSlotRef = db.collection('doctor_slots').doc(newSlotId);
      const slotSnap = await tx.get(newSlotRef);
      const currentActiveIds = (slotSnap.exists ? (slotSnap.data()?.activeAppointmentIds || []) : [])
        .filter((id) => id !== appointmentId);
      if (currentActiveIds.length >= MAX_PATIENTS_PER_SLOT) {
        throw new HttpsError(
          'resource-exhausted',
          `This time slot is full. Maximum ${MAX_PATIENTS_PER_SLOT} patients allowed at the same time.`,
        );
      }
      for (const existingId of currentActiveIds) {
        const existingApptSnap = await tx.get(db.collection('appointments').doc(existingId));
        if (!existingApptSnap.exists) continue;
        const existingData = existingApptSnap.data() || {};
        const existingName = String(existingData.patientName || '').trim().toLowerCase();
        const incomingName = String(fresh.patientName || callerData?.name || '').trim().toLowerCase();
        const samePerson = incomingName.length === 0 || existingName === incomingName;
        if (existingData.patientId === callerPatientId && !existingData.cancellationReason && samePerson) {
          throw new HttpsError(
            'failed-precondition',
            'You already have an active appointment in this time slot.',
          );
        }
      }
      if (currentActiveIds.length >= 1) {
        const slotShareReason = String(data?.slotShareReason || '').trim();
        if (!slotShareReason) {
          throw new HttpsError(
            'invalid-argument',
            'Please provide a reason for sharing this time slot.',
          );
        }
      }

      const oldSlotRef = db.collection('doctor_slots').doc(oldSlotId);
      tx.set(
        oldSlotRef,
        {
          activeAppointmentIds: FieldValue.arrayRemove(appointmentId),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      tx.set(
        newSlotRef,
        {
          doctorId,
          date: newDate,
          time: newTime,
          activeAppointmentIds: FieldValue.arrayUnion(appointmentId),
          updatedAt: FieldValue.serverTimestamp(),
          slotOverflow: currentActiveIds.length + 1 > MAX_PATIENTS_PER_SLOT,
        },
        { merge: true },
      );
    }

    tx.set(
      apptRef,
      {
        dateTime: dateTimeTimestamp,
        slotLabel,
        tokenNumber,
        patientStatus: 'confirmed',
        doctorStatus: 'confirmed',
        wasRescheduled: true,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  return {
    ok: true,
    appointmentId,
    doctorId,
    patientId: callerPatientId,
    tokenNumber,
    slotDate: newDate,
    slotTime: newTime,
  };
}

/**
 * Cloud Function Callable bookAppointment in asia-south1.
 */
const bookAppointment = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  async (request) => {
    assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
    const db = getFirestore();
    await enforceAbuseLimit(db, request, 'booking');
    return await bookAppointmentHandler(request.data, request.auth, db);
  },
);

const rescheduleAppointment = onCall(
  { region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  async (request) => {
    assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
    const db = getFirestore();
    await enforceAbuseLimit(db, request, 'booking');
    return await rescheduleAppointmentHandler(request.data, request.auth, db);
  },
);

module.exports = {
  MAX_PATIENTS_PER_SLOT,
  DEFAULT_DOCTOR_AVAILABILITY,
  FIRESTORE_TRIGGER_REGION,
  CALLABLE_REGION,
  ENFORCE_ABUSE_APP_CHECK,
  toIstDateAndTime,
  deriveSlotId,
  parseTimeToMinutes,
  isSlotInsideDoctorAvailability,
  buildAppointmentData,
  reconcileAppointmentSlotTransaction,
  reconcileAppointmentSlotHandler,
  bookAppointmentHandler,
  rescheduleAppointmentHandler,
  reconcileAppointmentSlot,
  bookAppointment,
  rescheduleAppointment,
};
