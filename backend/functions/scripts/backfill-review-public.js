/**
 * Backfills review_public from existing reviews documents.
 *
 * Usage (from functions/):
 *   set GOOGLE_APPLICATION_CREDENTIALS=...
 *   node scripts/backfill-review-public.js
 *   node scripts/backfill-review-public.js --apply
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { syncReviewPublicDoc } = require('../review_public_sync');

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'medibond-45fad';
const APPLY = process.argv.includes('--apply');

initializeApp({
  credential: applicationDefault(),
  projectId: PROJECT_ID,
});

const db = getFirestore();

async function main() {
  const snap = await db.collection('reviews').get();
  console.log(`Found ${snap.size} reviews in ${PROJECT_ID}`);
  console.log(`Mode: ${APPLY ? 'APPLY' : 'DRY-RUN'}`);

  let planned = 0;
  for (const doc of snap.docs) {
    planned += 1;
    console.log(`  review_public/${doc.id} <- reviews/${doc.id}`);
    if (APPLY) {
      await syncReviewPublicDoc(db, doc.id, doc.data() || {});
    }
  }

  console.log(`\n${planned} public projections ${APPLY ? 'written' : 'planned'}.`);
  if (!APPLY && planned > 0) {
    console.log('Re-run with --apply to write.');
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
