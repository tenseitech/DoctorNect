/**
 * DoctorNect: Doctor Slots Backfill Script
 * File: backend/scripts/backfill_doctor_slots.js
 * 
 * Purpose:
 * Backfills doctor_slots/{slotId} documents from active appointments
 * for double-booking prevention (Design A).
 * 
 * Modes:
 *   - Dry run (DEFAULT, READ-ONLY, prints counts only, NO WRITES):
 *       node backend/scripts/backfill_doctor_slots.js
 *   - Apply changes:
 *       node backend/scripts/backfill_doctor_slots.js --apply
 * 
 * Safety:
 *   - Dry-run by default.
 *   - Batches writes in chunks <= 400 docs per WriteBatch (below Firestore 500 limit).
 *   - Flags slots with activeCount > 3 as slotOverflow: true without dropping records.
 */

'use strict';

const fs = require('fs');
const path = require('path');

// Safe environment loading
const loadEnvPath = path.join(__dirname, 'load_env.js');
if (fs.existsSync(loadEnvPath)) {
  try {
    require('./load_env').loadEnv();
  } catch (_) {}
}

const admin = require('firebase-admin');

const args = process.argv.slice(2);
const IS_APPLY = args.includes('--apply');
const MAX_PATIENTS_PER_SLOT = 3;

function initFirebaseAdmin() {
  if (admin.apps.length > 0) return admin.app();

  const saCandidates = [
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    path.join(__dirname, 'service-account.json'),
    path.join(process.cwd(), 'service-account.json'),
  ];
  const saPath = saCandidates.find((p) => p && fs.existsSync(p));

  if (saPath) {
    const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    return admin.initializeApp({
      credential: admin.credential.cert(sa),
    });
  }

  return admin.initializeApp({
    projectId: process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID || 'medibond-45fad',
  });
}

function toIstDateAndTime(input) {
  let date;
  if (!input) return null;
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

  if (isNaN(date.getTime())) return null;

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
  let year = '', month = '', day = '', hour = '', minute = '';
  for (const part of parts) {
    if (part.type === 'year') year = part.value;
    else if (part.type === 'month') month = part.value;
    else if (part.type === 'day') day = part.value;
    else if (part.type === 'hour') hour = part.value;
    else if (part.type === 'minute') minute = part.value;
  }

  return {
    date: `${year}-${month}-${day}`,
    time: `${hour}:${minute}`,
  };
}

function deriveSlotId(doctorId, dateTime) {
  const cleanDoctorId = String(doctorId || '').trim();
  if (!cleanDoctorId) return null;
  const ist = toIstDateAndTime(dateTime);
  if (!ist) return null;
  return `${cleanDoctorId}_${ist.date}_${ist.time}`;
}

async function runBackfill() {
  console.log(`\n=== Doctor Slots Backfill (Design A) ===`);
  console.log(`Mode: ${IS_APPLY ? 'APPLY (Writing changes to Firestore)' : 'DRY RUN (Read-only, counts only)'}\n`);

  initFirebaseAdmin();
  const db = admin.firestore();

  const appointmentsSnap = await db.collection('appointments').get();
  console.log(`Total appointments found in Firestore: ${appointmentsSnap.size}`);

  let activeCount = 0;
  let cancelledCount = 0;
  let invalidCount = 0;

  // Map of slotId -> { doctorId, date, time, activeAppointmentIds: [] }
  const slotMap = new Map();

  for (const doc of appointmentsSnap.docs) {
    const data = doc.data() || {};
    const appointmentId = doc.id;

    if (!data.doctorId || !data.dateTime) {
      invalidCount++;
      continue;
    }

    if (data.cancellationReason) {
      cancelledCount++;
      continue;
    }

    const slotId = deriveSlotId(data.doctorId, data.dateTime);
    if (!slotId) {
      invalidCount++;
      continue;
    }

    activeCount++;
    const ist = toIstDateAndTime(data.dateTime);

    if (!slotMap.has(slotId)) {
      slotMap.set(slotId, {
        slotId,
        doctorId: data.doctorId,
        date: ist.date,
        time: ist.time,
        activeAppointmentIds: [appointmentId],
      });
    } else {
      const entry = slotMap.get(slotId);
      if (!entry.activeAppointmentIds.includes(appointmentId)) {
        entry.activeAppointmentIds.push(appointmentId);
      }
    }
  }

  const uniqueSlots = slotMap.size;
  const overflowSlots = [];
  for (const [slotId, entry] of slotMap.entries()) {
    if (entry.activeAppointmentIds.length > MAX_PATIENTS_PER_SLOT) {
      overflowSlots.push({
        slotId,
        count: entry.activeAppointmentIds.length,
        appointmentIds: entry.activeAppointmentIds,
      });
    }
  }

  console.log(`\n--- Backfill Statistics ---`);
  console.log(`Total Scanned:           ${appointmentsSnap.size}`);
  console.log(`Active Appointments:     ${activeCount}`);
  console.log(`Cancelled (Skipped):     ${cancelledCount}`);
  console.log(`Invalid / Missing Data:  ${invalidCount}`);
  console.log(`Unique Slots to Create:  ${uniqueSlots}`);
  console.log(`Overflow Slots (> ${MAX_PATIENTS_PER_SLOT}):     ${overflowSlots.length}`);

  if (overflowSlots.length > 0) {
    console.log(`\n[WARNING] Slots currently exceeding max capacity (${MAX_PATIENTS_PER_SLOT}):`);
    for (const ov of overflowSlots) {
      console.log(`  Slot ${ov.slotId}: ${ov.count} bookings (${ov.appointmentIds.join(', ')})`);
    }
  }

  if (!IS_APPLY) {
    console.log(`\n[DRY RUN COMPLETED] No writes were performed to Firestore.`);
    console.log(`To apply these slots to Firestore, run:\n  node backend/scripts/backfill_doctor_slots.js --apply\n`);
    return;
  }

  console.log(`\nApplying slot documents to collection 'doctor_slots'...`);
  const slotEntries = Array.from(slotMap.values());
  const BATCH_SIZE = 400;
  let batch = db.batch();
  let opsInBatch = 0;
  let batchesCommitted = 0;
  let totalWritten = 0;

  for (const entry of slotEntries) {
    const slotRef = db.collection('doctor_slots').doc(entry.slotId);
    const isOverflow = entry.activeAppointmentIds.length > MAX_PATIENTS_PER_SLOT;

    batch.set(
      slotRef,
      {
        doctorId: entry.doctorId,
        date: entry.date,
        time: entry.time,
        activeAppointmentIds: entry.activeAppointmentIds,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        slotOverflow: isOverflow,
      },
      { merge: true },
    );

    opsInBatch++;
    totalWritten++;

    if (opsInBatch >= BATCH_SIZE) {
      await batch.commit();
      batchesCommitted++;
      console.log(`Committed batch ${batchesCommitted} (${opsInBatch} slots)...`);
      batch = db.batch();
      opsInBatch = 0;
    }
  }

  if (opsInBatch > 0) {
    await batch.commit();
    batchesCommitted++;
    console.log(`Committed final batch ${batchesCommitted} (${opsInBatch} slots)...`);
  }

  console.log(`\n[APPLY COMPLETED] Successfully created/updated ${totalWritten} doctor_slots across ${batchesCommitted} batches.\n`);
}

if (require.main === module) {
  runBackfill().catch((err) => {
    console.error('[backfill_doctor_slots] Failed:', err);
    process.exit(1);
  });
}

module.exports = {
  runBackfill,
  deriveSlotId,
  toIstDateAndTime,
};
