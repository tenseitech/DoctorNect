/**
 * Diagnose lab booking in_app_notifications recipientUid mismatch.
 *
 * Usage (from functions/):
 *   node scripts/diagnose-lab-inapp-recipient.js
 *
 * Optional env:
 *   NOTIF_DOC_ID=...     specific in_app_notifications doc id
 *   OWNER_UID=...        search patients by ownerUid
 *   BOOKING_ID=...       load lab_bookings/{id}
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = 'medibond-45fad';
const UID_A = 'sjmXccxZjzaSL5XKoxUiEcGU4vi1';
const UID_B = 'gAh0ghYAYOYwiZRYD2xJ6lygjmy1';

initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });

async function patientsByOwnerUid(db, ownerUid) {
  const snap = await db.collection('patients').where('ownerUid', '==', ownerUid).get();
  return snap.docs.map((doc) => ({
    patientId: doc.id,
    ownerUid: doc.data()?.ownerUid || null,
    name: doc.data()?.name || doc.data()?.fullName || null,
    email: doc.data()?.email || null,
  }));
}

async function userProfile(db, uid) {
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  return {
    uid,
    email: data.email || null,
    role: data.role || null,
    profileId: data.profileId || null,
  };
}

async function recentLabInAppNotifications(db, limit = 10) {
  const snap = await db
    .collection('in_app_notifications')
    .orderBy('createdAt', 'desc')
    .limit(limit)
    .get();
  return snap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter(
      (n) =>
        String(n.dedupeKey || '').startsWith('p_lab_') ||
        String(n.sourceEvent || '').includes('lab_booking'),
    );
}

async function main() {
  const db = getFirestore();

  console.log('=== Patients by ownerUid ===');
  for (const uid of [UID_A, UID_B]) {
    const matches = await patientsByOwnerUid(db, uid);
    console.log(`ownerUid=${uid} -> ${matches.length} patient doc(s)`);
    for (const p of matches) {
      console.log(' ', JSON.stringify(p));
    }
  }

  console.log('\n=== users/{uid} profiles ===');
  for (const uid of [UID_A, UID_B]) {
    const profile = await userProfile(db, uid);
    console.log(uid, profile ? JSON.stringify(profile) : '(no users doc)');
  }

  const bookingId = process.env.BOOKING_ID?.trim();
  if (bookingId) {
    console.log(`\n=== lab_bookings/${bookingId} ===`);
    const bookingSnap = await db.collection('lab_bookings').doc(bookingId).get();
    if (!bookingSnap.exists) {
      console.log('booking not found');
    } else {
      const data = bookingSnap.data();
      console.log(JSON.stringify({
        bookingId: bookingSnap.id,
        patientId: data.patientId || null,
        status: data.status || null,
        testName: data.testName || null,
        partnerLab: data.partnerLab || null,
      }, null, 2));
      if (data.patientId) {
        const patientSnap = await db.collection('patients').doc(data.patientId).get();
        console.log('linked patients doc:', patientSnap.exists
          ? JSON.stringify({ id: patientSnap.id, ownerUid: patientSnap.data()?.ownerUid || null })
          : 'MISSING');
      }
    }
  }

  const notifDocId = process.env.NOTIF_DOC_ID?.trim();
  if (notifDocId) {
    console.log(`\n=== in_app_notifications/${notifDocId} ===`);
    const notifSnap = await db.collection('in_app_notifications').doc(notifDocId).get();
    console.log(notifSnap.exists ? JSON.stringify(notifSnap.data(), null, 2) : 'not found');
  }

  console.log('\n=== Recent lab-related in_app_notifications (latest 10 collection-wide) ===');
  const recent = await recentLabInAppNotifications(db, 10);
  if (recent.length === 0) {
    console.log('none found in latest 10 notifications');
  }
  for (const n of recent) {
    console.log(JSON.stringify({
      id: n.id,
      recipientUid: n.recipientUid,
      recipientProfileId: n.recipientProfileId,
      dedupeKey: n.dedupeKey,
      sourceEvent: n.sourceEvent,
      sourceId: n.sourceId,
      title: n.title,
    }));
    if (n.recipientProfileId) {
      const pSnap = await db.collection('patients').doc(n.recipientProfileId).get();
      console.log('  patients/{recipientProfileId}.ownerUid =',
        pSnap.exists ? pSnap.data()?.ownerUid : '(missing patient doc)');
    }
    if (n.sourceId) {
      const bSnap = await db.collection('lab_bookings').doc(n.sourceId).get();
      console.log('  lab_bookings/{sourceId}.patientId =',
        bSnap.exists ? bSnap.data()?.patientId : '(missing booking doc)');
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
