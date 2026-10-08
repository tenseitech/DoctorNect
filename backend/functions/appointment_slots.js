'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');

const MAX_PATIENTS_PER_SLOT = 3;
const FIRESTORE_TRIGGER_REGION = 'asia-south2';
const CALLABLE_REGION = 'asia-south1';

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
}) {
  const patientName = String(data?.patientName || callerData?.name || '').trim();
  const patientAge = Number(data?.patientAge) || Number(callerData?.age) || 0;
  const patientGender = String(data?.patientGender || callerData?.gender || 'Male').trim();
  const doctorName = String(doctorData?.name || doctorData?.doctorName || data?.doctorName || '').trim();
  const specialization = String(doctorData?.specialization || data?.specialization || '').trim();
  const slotLabel = String(data?.slotLabel || '').trim();
  const tokenNumber = Number(data?.tokenNumber) || 1;
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
    tokenNumber,
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
    wasRescheduled: Boolean(data?.wasRescheduled),
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

/**
 * Handler for the appointments/{appointmentId} Firestore trigger.
 */
async function reconcileAppointmentSlotHandler(event, db = getFirestore()) {
  const before = event.data?.before?.data() || null;
  const after = event.data?.after?.data() || null;
  const appointmentId = event.params?.appointmentId || event.data?.after?.id || event.data?.before?.id;

  if (!appointmentId) return;

  const beforeActive = Boolean(before && before.doctorId && before.dateTime && !before.cancellationReason);
  const afterActive = Boolean(after && after.doctorId && after.dateTime && !after.cancellationReason);

  await reconcileAppointmentSlotTransaction(db, {
    appointmentId,
    beforeActive,
    beforeDoctorId: before?.doctorId,
    beforeDateTime: before?.dateTime,
    afterActive,
    afterDoctorId: after?.doctorId,
    afterDateTime: after?.dateTime,
  });
}

/**
 * Handler for the callable bookAppointment.
 */
async function bookAppointmentHandler(data, auth, db = getFirestore()) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to book an appointment.');
  }

  // 1. Verify caller is a patient
  const callerSnap = await db.collection('users').doc(auth.uid).get();
  if (!callerSnap.exists) {
    throw new HttpsError('permission-denied', 'User profile not found.');
  }
  const callerData = callerSnap.data() || {};
  if (callerData.role !== 'patient') {
    throw new HttpsError('permission-denied', 'Only patients can book appointments.');
  }
  const patientId = String(callerData.profileId || auth.uid).trim();

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
  const dateTimeRaw = data?.dateTime;
  if (!dateTimeRaw) {
    throw new HttpsError('invalid-argument', 'dateTime is required.');
  }

  let dateTimeTimestamp;
  if (typeof dateTimeRaw.toDate === 'function') {
    dateTimeTimestamp = dateTimeRaw;
  } else if (dateTimeRaw instanceof Date) {
    dateTimeTimestamp = Timestamp.fromDate(dateTimeRaw);
  } else if (typeof dateTimeRaw === 'string' || typeof dateTimeRaw === 'number') {
    dateTimeTimestamp = Timestamp.fromDate(new Date(dateTimeRaw));
  } else if (dateTimeRaw._seconds !== undefined) {
    dateTimeTimestamp = new Timestamp(dateTimeRaw._seconds, dateTimeRaw._nanoseconds || 0);
  } else if (dateTimeRaw.seconds !== undefined) {
    dateTimeTimestamp = new Timestamp(dateTimeRaw.seconds, dateTimeRaw.nanoseconds || 0);
  } else {
    throw new HttpsError('invalid-argument', 'Invalid dateTime format.');
  }

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

  // 5. In ONE transaction: check capacity, check patient double-booking, create appointment, add to slot
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
        if (existingData.patientId === patientId && !existingData.cancellationReason) {
          throw new HttpsError(
            'failed-precondition',
            'You already have an active appointment in this time slot.'
          );
        }
      }
    }

    // Build appointment matching AppointmentFirestoreMapper
    const appointmentDoc = buildAppointmentData({
      appointmentId,
      doctorId,
      doctorData,
      patientId,
      callerData,
      data,
      dateTimeTimestamp,
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
 * Cloud Function Callable bookAppointment in asia-south1.
 */
const bookAppointment = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    return await bookAppointmentHandler(request.data, request.auth);
  },
);

module.exports = {
  MAX_PATIENTS_PER_SLOT,
  DEFAULT_DOCTOR_AVAILABILITY,
  FIRESTORE_TRIGGER_REGION,
  CALLABLE_REGION,
  toIstDateAndTime,
  deriveSlotId,
  parseTimeToMinutes,
  isSlotInsideDoctorAvailability,
  buildAppointmentData,
  reconcileAppointmentSlotTransaction,
  reconcileAppointmentSlotHandler,
  bookAppointmentHandler,
  reconcileAppointmentSlot,
  bookAppointment,
};
