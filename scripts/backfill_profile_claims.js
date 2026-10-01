/**
 * DoctorNect: Profile Claims Backfill Script
 * File: scripts/backfill_profile_claims.js
 * 
 * Purpose:
 * Backfills profile_claims/{profileId} for existing Firestore users
 * to enforce atomic profile ownership verification.
 * 
 * Modes:
 *   - Dry run (DEFAULT, READ-ONLY):
 *       node scripts/backfill_profile_claims.js
 *   - Apply changes:
 *       node scripts/backfill_profile_claims.js --apply
 * 
 * Safety:
 *   - Skips users where profileId is already claimed by another UID and logs conflicts.
 *   - Does not overwrite existing claims.
 *   - Verifies whether profile docs exist in matching role collections.
 *   - Writes audit results to scripts/backfill_profile_claims_report.json.
 */

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

const ROLE_COLLECTIONS = {
  doctor: 'doctors',
  patient: 'patients',
  medicalStore: 'medical_stores',
  lab: 'labs',
  ambulance: 'ambulances',
};

function initFirebaseAdmin() {
  if (admin.apps.length > 0) return admin.app();

  const saCandidates = [
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    path.join(__dirname, 'service-account.json'),
    path.join(process.cwd(), 'service-account.json'),
  ];
  const saPath = saCandidates.find(p => p && fs.existsSync(p));

  if (saPath) {
    const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    return admin.initializeApp({
      credential: admin.credential.cert(sa),
      projectId: sa.project_id || 'medibond-45fad',
    });
  }

  return admin.initializeApp({ projectId: 'medibond-45fad' });
}

async function runBackfill() {
  console.log('======================================================');
  console.log(`    DOCTORNECT PROFILE CLAIMS BACKFILL (${IS_APPLY ? 'APPLY MODE' : 'DRY RUN'})    `);
  console.log('======================================================\n');

  initFirebaseAdmin();
  const db = admin.firestore();

  console.log('[Backfill] Reading existing profile_claims collection...');
  const claimsSnapshot = await db.collection('profile_claims').get();
  const existingClaims = new Map(); // profileId -> uid
  for (const doc of claimsSnapshot.docs) {
    existingClaims.set(doc.id, doc.data().uid);
  }
  console.log(`[Backfill] Found ${existingClaims.size} existing claims.`);

  console.log('[Backfill] Reading all documents from users collection...');
  const usersSnapshot = await db.collection('users').get();
  console.log(`[Backfill] Found ${usersSnapshot.size} user documents.`);

  const toCreate = [];
  const conflicts = [];
  const alreadyClaimed = [];
  const missingProfileId = [];
  const missingProfileDoc = [];

  for (const doc of usersSnapshot.docs) {
    const uid = doc.id;
    const data = doc.data() || {};
    const profileId = data.profileId ? String(data.profileId).trim() : null;
    const role = data.role || 'patient';

    if (!profileId) {
      missingProfileId.push({ uid, role });
      continue;
    }

    // Verify existence of profile document in matching collection
    const targetCollection = ROLE_COLLECTIONS[role];
    if (targetCollection) {
      const profileDocSnap = await db.collection(targetCollection).doc(profileId).get();
      if (!profileDocSnap.exists) {
        missingProfileDoc.push({
          uid,
          profileId,
          role,
          expectedCollection: targetCollection,
        });
      }
    }

    if (existingClaims.has(profileId)) {
      const claimingUid = existingClaims.get(profileId);
      if (claimingUid === uid) {
        alreadyClaimed.push({ profileId, uid });
      } else {
        conflicts.push({
          profileId,
          userUid: uid,
          claimedByUid: claimingUid,
          role
        });
      }
    } else {
      toCreate.push({
        profileId,
        uid,
        role,
        createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp()
      });
      // Track in map so duplicate users in the same batch get flagged as conflicts
      existingClaims.set(profileId, uid);
    }
  }

  console.log(`\n--- Plan Summary ---`);
  console.log(`Claims to create:        ${toCreate.length}`);
  console.log(`Already claimed (match): ${alreadyClaimed.length}`);
  console.log(`Conflicts (mismatches):  ${conflicts.length}`);
  console.log(`Users without profileId: ${missingProfileId.length}`);
  console.log(`Users missing profile doc: ${missingProfileDoc.length}`);

  if (IS_APPLY) {
    console.log('\n[Backfill] Applying claims in batches of 400...');
    const BATCH_SIZE = 400;
    for (let i = 0; i < toCreate.length; i += BATCH_SIZE) {
      const chunk = toCreate.slice(i, i + BATCH_SIZE);
      const batch = db.batch();
      for (const item of chunk) {
        const ref = db.collection('profile_claims').doc(item.profileId);
        batch.set(ref, {
          uid: item.uid,
          role: item.role,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          backfilled: true,
          backfilledAt: admin.firestore.FieldValue.serverTimestamp()
        });
      }
      await batch.commit();
      console.log(`  Committed batch ${Math.floor(i / BATCH_SIZE) + 1}/${Math.ceil(toCreate.length / BATCH_SIZE)}`);
    }
    console.log('[Backfill] All claims successfully committed.');
  } else {
    console.log('\n[Dry Run] No writes performed. Re-run with --apply to commit these claims.');
  }

  const report = {
    executedAt: new Date().toISOString(),
    isApply: IS_APPLY,
    stats: {
      totalUsers: usersSnapshot.size,
      claimsToCreateCount: toCreate.length,
      alreadyClaimedCount: alreadyClaimed.length,
      conflictsCount: conflicts.length,
      missingProfileIdCount: missingProfileId.length,
      missingProfileDocCount: missingProfileDoc.length,
    },
    conflicts,
    missingProfileId,
    missingProfileDoc,
  };

  const reportPath = path.join(__dirname, 'backfill_profile_claims_report.json');
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), 'utf8');
  console.log(`[Backfill] Detailed audit report written to: ${reportPath}\n`);

  return report;
}

if (require.main === module) {
  runBackfill().catch(err => {
    console.error('[Backfill Error]:', err.message);
    process.exit(1);
  });
}

module.exports = { runBackfill };
