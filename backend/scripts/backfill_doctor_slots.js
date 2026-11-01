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

const { createRequire } = require('module');
let admin;
let FieldValue;
try {
  admin = require('firebase-admin');
  FieldValue = require('firebase-admin/firestore').FieldValue;
} catch (_) {
  try {
    const fnReq = createRequire(path.resolve(__dirname, '..', 'functions', 'package.json'));
    admin = fnReq('firebase-admin');
    FieldValue = fnReq('firebase-admin/firestore').FieldValue;
  } catch (err) {
    admin = null;
    FieldValue = null;
  }
}

const args = process.argv.slice(2);
const IS_APPLY = args.includes('--apply');
const MAX_PATIENTS_PER_SLOT = 3;

function getProjectArg() {
  const projectIdx = args.findIndex((a) => a === '--project');
  if (projectIdx !== -1 && args[projectIdx + 1] && !args[projectIdx + 1].startsWith('--')) {
    return args[projectIdx + 1].trim();
  }
  const eqArg = args.find((a) => a.startsWith('--project='));
  if (eqArg) {
    return eqArg.split('=')[1]?.trim() || null;
  }
  return null;
}

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
      projectId: sa.project_id,
    });
  }

  return admin.initializeApp({
    projectId: process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID || 'medibond-45fad',
  });
}

let appointmentSlotsModule;
try {
  appointmentSlotsModule = require('../functions/appointment_slots');
} catch (_) {
  const fnReq = createRequire(path.resolve(__dirname, '..', 'functions', 'package.json'));
  appointmentSlotsModule = fnReq('./appointment_slots');
}
const { deriveSlotId, toIstDateAndTime } = appointmentSlotsModule;

async function backfillSingleSlotTransaction(db, entry) {
  const slotRef = db.collection('doctor_slots').doc(entry.slotId);

  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(slotRef);
    const existingData = snap.exists ? snap.data() : null;
    const existingIds = Array.isArray(existingData?.activeAppointmentIds)
      ? existingData.activeAppointmentIds
      : [];

    const allCandidateIds = Array.from(new Set([...existingIds, ...entry.activeAppointmentIds]));
    const verifiedActiveIds = [];

    // Inside transaction, re-read every appointment doc in that slot
    for (const apptId of allCandidateIds) {
      const apptSnap = await tx.get(db.collection('appointments').doc(apptId));
      if (apptSnap.exists) {
        const apptData = apptSnap.data() || {};
        const isCancelled = Boolean(apptData.cancellationReason);
        const doctorMatches = String(apptData.doctorId || '').trim() === entry.doctorId;
        let slotMatches = false;
        try {
          slotMatches = Boolean(apptData.doctorId && apptData.dateTime) &&
            deriveSlotId(apptData.doctorId, apptData.dateTime) === entry.slotId;
        } catch (_) {
          slotMatches = false;
        }

        // Add ID only if still active (cancellationReason null and doctorId, dateTime still match this slot)
        if (!isCancelled && doctorMatches && slotMatches) {
          verifiedActiveIds.push(apptId);
        }
      }
    }

    const isOverflow = verifiedActiveIds.length > MAX_PATIENTS_PER_SLOT;

    tx.set(
      slotRef,
      {
        doctorId: entry.doctorId,
        date: entry.date,
        time: entry.time,
        activeAppointmentIds: verifiedActiveIds,
        updatedAt: FieldValue.serverTimestamp(),
        slotOverflow: isOverflow,
      },
      { merge: true },
    );

    return { slotId: entry.slotId, verifiedActiveIds, isOverflow };
  });
}

async function scanAppointmentsForSlots(db) {
  const appointmentsSnap = await db.collection('appointments').get();
  let activeCount = 0;
  let cancelledCount = 0;
  let invalidCount = 0;
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

    let slotId = null;
    let ist = null;
    try {
      slotId = deriveSlotId(data.doctorId, data.dateTime);
      ist = toIstDateAndTime(data.dateTime);
    } catch (_) {
      invalidCount++;
      continue;
    }

    if (!slotId) {
      invalidCount++;
      continue;
    }

    activeCount++;

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

  return {
    totalScanned: appointmentsSnap.size,
    activeCount,
    cancelledCount,
    invalidCount,
    slotMap,
  };
}

const { bootstrapMutatingScript } = require('../../scripts/lib/mutating_script_bootstrap');

async function runBackfill() {
  bootstrapMutatingScript('backend/scripts/backfill_doctor_slots.js');
  const app = initFirebaseAdmin();
  const db = admin.firestore();

  let connectedProjectId = app.options.projectId
    || (app.options.credential && app.options.credential.projectId)
    || db.projectId
    || process.env.GCLOUD_PROJECT
    || process.env.FIREBASE_PROJECT_ID;

  const projectFlag = getProjectArg();

  console.log(`\n=== Doctor Slots Backfill (Design A) ===`);
  console.log(`Connected Project ID: ${connectedProjectId || '(unknown)'}`);
  console.log(`Mode: ${IS_APPLY ? 'APPLY (Writing changes to Firestore)' : 'DRY RUN (Read-only, counts only)'}\n`);

  if (IS_APPLY) {
    if (!projectFlag) {
      throw new Error(
        'Safety check failed: --apply requires explicit --project <projectId> flag (e.g. node backfill_doctor_slots.js --apply --project medibond-45fad). Refusing to run.',
      );
    }
    if (projectFlag !== connectedProjectId) {
      throw new Error(
        `Safety check failed: --project flag "${projectFlag}" does not match connected project "${connectedProjectId}". Refusing to run.`,
      );
    }
  }

  // Print project id before any read
  console.log(`Target project verified: ${connectedProjectId}`);
  console.log(`Starting Firestore read from 'appointments'...\n`);

  const {
    totalScanned,
    activeCount,
    cancelledCount,
    invalidCount,
    slotMap,
  } = await scanAppointmentsForSlots(db);

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

  // --- Comparison Mode (Read-Only) ---
  console.log(`\n--- Stored doctor_slots Comparison (Read-only) ---`);
  console.log(`Scanning existing 'doctor_slots' collection to detect drift...`);

  const existingSlotsSnap = await db.collection('doctor_slots').get();
  const existingSlotMap = new Map();
  for (const doc of existingSlotsSnap.docs) {
    existingSlotMap.set(doc.id, doc.data() || {});
  }

  let matchingCount = 0;
  let missingInDbCount = 0;
  let differingCount = 0;
  let orphanSlotsCount = 0;
  const diffDetails = [];

  for (const [slotId, entry] of slotMap.entries()) {
    const existing = existingSlotMap.get(slotId);
    if (!existing) {
      missingInDbCount++;
      diffDetails.push({
        slotId,
        type: 'MISSING_IN_DB',
        scannedCount: entry.activeAppointmentIds.length,
        scannedIds: entry.activeAppointmentIds,
        storedCount: 0,
        storedIds: [],
      });
    } else {
      const storedIds = Array.isArray(existing.activeAppointmentIds) ? existing.activeAppointmentIds : [];
      const scannedSet = new Set(entry.activeAppointmentIds);
      const storedSet = new Set(storedIds);

      const arraysEqual =
        scannedSet.size === storedSet.size &&
        [...scannedSet].every((id) => storedSet.has(id));

      if (arraysEqual) {
        matchingCount++;
      } else {
        differingCount++;
        diffDetails.push({
          slotId,
          type: 'ARRAY_DIFF',
          scannedCount: entry.activeAppointmentIds.length,
          scannedIds: entry.activeAppointmentIds,
          storedCount: storedIds.length,
          storedIds,
        });
      }
    }
  }

  for (const [slotId, data] of existingSlotMap.entries()) {
    if (!slotMap.has(slotId) && Array.isArray(data.activeAppointmentIds) && data.activeAppointmentIds.length > 0) {
      orphanSlotsCount++;
      diffDetails.push({
        slotId,
        type: 'ORPHAN_IN_DB',
        scannedCount: 0,
        scannedIds: [],
        storedCount: data.activeAppointmentIds.length,
        storedIds: data.activeAppointmentIds,
      });
    }
  }

  console.log(`Stored doctor_slots in DB:     ${existingSlotsSnap.size}`);
  console.log(`Matching slots (in sync):       ${matchingCount}`);
  console.log(`Slots missing in DB:            ${missingInDbCount}`);
  console.log(`Differing slots (drifted):      ${differingCount}`);
  console.log(`Orphan active slots in DB:      ${orphanSlotsCount}`);

  if (diffDetails.length > 0) {
    console.log(`\n[DRIFT DETAILS] Differences detected (top 20):`);
    for (const d of diffDetails.slice(0, 20)) {
      if (d.type === 'MISSING_IN_DB') {
        console.log(`  [MISSING] ${d.slotId}: Not in DB (scanned ${d.scannedCount} IDs: ${d.scannedIds.join(', ')})`);
      } else if (d.type === 'ARRAY_DIFF') {
        console.log(`  [DIFF]    ${d.slotId}: DB has ${d.storedCount} IDs [${d.storedIds.join(', ')}] vs Scanned ${d.scannedCount} IDs [${d.scannedIds.join(', ')}]`);
      } else if (d.type === 'ORPHAN_IN_DB') {
        console.log(`  [ORPHAN]  ${d.slotId}: DB has ${d.storedCount} IDs [${d.storedIds.join(', ')}] but appointments scanned 0 active`);
      }
    }
    if (diffDetails.length > 20) {
      console.log(`  ... and ${diffDetails.length - 20} more differing slots.`);
    }
  } else {
    console.log(`\nAll doctor_slots match appointments perfectly. Zero drift!`);
  }

  if (!IS_APPLY) {
    console.log(`\n[DRY RUN COMPLETED] No writes were performed to Firestore.`);
    console.log(`To apply these slots safely to Firestore, run:\n  node backend/scripts/backfill_doctor_slots.js --apply --project <projectId>\n`);
    return;
  }

  console.log(`\nApplying slot documents to collection 'doctor_slots' safely using transactions...`);
  const slotEntries = Array.from(slotMap.values());
  let totalWritten = 0;

  for (const entry of slotEntries) {
    await backfillSingleSlotTransaction(db, entry);
    totalWritten++;
    if (totalWritten % 100 === 0 || totalWritten === slotEntries.length) {
      console.log(`Committed transaction ${totalWritten}/${slotEntries.length} slots...`);
    }
  }

  console.log(`\n[APPLY COMPLETED] Successfully created/merged ${totalWritten} doctor_slots via transactions.\n`);
}

if (require.main === module) {
  runBackfill().catch((err) => {
    console.error('[backfill_doctor_slots] Failed:', err);
    process.exit(1);
  });
}

module.exports = {
  runBackfill,
  scanAppointmentsForSlots,
  backfillSingleSlotTransaction,
  deriveSlotId,
  toIstDateAndTime,
};
