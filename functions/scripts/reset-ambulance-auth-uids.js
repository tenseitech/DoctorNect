/**
 * One-time emergency migration: clears authUid on every ambulances document so
 * drivers can reclaim on next login after Phase 1 rules deploy.
 *
 * Prefer resyncAmbulanceAuthUid (callable) for zero-downtime recovery. Only run
 * this script if you need every driver reset before a maintenance window.
 *
 * Usage (from functions/ directory, with Application Default Credentials):
 *   node scripts/reset-ambulance-auth-uids.js
 *   node scripts/reset-ambulance-auth-uids.js --dry-run
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

initializeApp({ credential: applicationDefault() });

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  const db = getFirestore();
  const snapshot = await db.collection('ambulances').get();

  let updated = 0;
  for (const doc of snapshot.docs) {
    const current = String(doc.data().authUid || '');
    if (current === '') continue;

    console.log(`${dryRun ? '[dry-run] ' : ''}Reset authUid for ${doc.id} (was ${current.slice(0, 8)}…)`);
    if (!dryRun) {
      await doc.ref.set({ authUid: '' }, { merge: true });
    }
    updated += 1;
  }

  console.log(`Done. ${updated} document(s) ${dryRun ? 'would be' : 'were'} reset.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
