/**
 * DoctorNect: Firebase Auth & S3 Test User Purge Script
 *
 * SAFETY INVARIANTS:
 * 1. Default mode is STRICTLY DRY-RUN. Zero mutations occur without explicit confirmation.
 * 2. Live purge requires:
 *      --confirm-prod-purge=doctornect-production
 * 3. Never auto-runs; must be manually invoked by an authorized administrator.
 * 4. Phone targets are loaded dynamically from environment or gitignored config; zero hardcoded phones.
 *
 * Usage:
 *   # Dry run audit:
 *   node backend/scripts/purge_firebase_test_users_and_s3.js --dry-run
 *
 *   # Live purge:
 *   node backend/scripts/purge_firebase_test_users_and_s3.js --confirm-prod-purge=doctornect-production
 */

require('./load_env').loadEnv();
const fs = require('fs');
const path = require('path');

// Ensure module resolution finds packages in backend/functions/node_modules
module.paths.push(path.join(__dirname, '../functions/node_modules'));
module.paths.push(path.join(__dirname, '../node_modules'));

let adminApp, adminAuth;
try {
  adminApp = require('firebase-admin/app');
  adminAuth = require('firebase-admin/auth');
} catch (e) {
  adminApp = null;
  adminAuth = null;
}

let S3Client, ListObjectsV2Command, DeleteObjectsCommand;
try {
  ({ S3Client, ListObjectsV2Command, DeleteObjectsCommand } = require('@aws-sdk/client-s3'));
} catch (err) {
  S3Client = null;
}

function loadDemoPhones() {
  if (process.env.DEMO_PHONES) {
    return process.env.DEMO_PHONES.split(',').map((p) => p.trim()).filter(Boolean);
  }
  if (process.env.DEMO_PHONES_CONFIG) {
    try {
      const configPath = path.resolve(process.cwd(), process.env.DEMO_PHONES_CONFIG);
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, 'utf8');
        const parsed = JSON.parse(raw);
        const phones = parsed.demo_phones || parsed.phones || parsed;
        if (Array.isArray(phones)) return phones.map((p) => String(p).trim()).filter(Boolean);
      }
      const inline = JSON.parse(process.env.DEMO_PHONES_CONFIG);
      const phones = inline.demo_phones || inline.phones || inline;
      if (Array.isArray(phones)) return phones.map((p) => String(p).trim()).filter(Boolean);
    } catch (e) {
      console.warn(`Warning: failed to parse DEMO_PHONES_CONFIG: ${e.message}`);
    }
  }
  const candidatePaths = [
    path.join(__dirname, 'demo_phones.json'),
    path.join(__dirname, '../demo_phones.json'),
    path.join(process.cwd(), 'demo_phones.json'),
  ];
  for (const candidate of candidatePaths) {
    if (fs.existsSync(candidate)) {
      try {
        const raw = fs.readFileSync(candidate, 'utf8');
        const parsed = JSON.parse(raw);
        const phones = parsed.demo_phones || parsed.phones || parsed;
        if (Array.isArray(phones)) return phones.map((p) => String(p).trim()).filter(Boolean);
      } catch (e) {
        console.warn(`Warning: failed to read ${candidate}: ${e.message}`);
      }
    }
  }
  return [];
}

const DEMO_PHONES = loadDemoPhones();
const REQUIRED_CONFIRM_TOKEN = 'doctornect-production';

const args = process.argv.slice(2);
const hasLiveFlag = args.includes('--live') || args.some((a) => a.startsWith('--confirm-prod-purge='));
const confirmArg = args.find((a) => a.startsWith('--confirm-prod-purge='));
const confirmToken = confirmArg ? confirmArg.split('=')[1] : null;

const isLive = hasLiveFlag && confirmToken === REQUIRED_CONFIRM_TOKEN;
const isDryRun = !isLive;

if (hasLiveFlag && confirmToken !== REQUIRED_CONFIRM_TOKEN) {
  console.error('================================================================');
  console.error('FATAL: Purge rejected.');
  console.error(`Live purge requires: --confirm-prod-purge=${REQUIRED_CONFIRM_TOKEN}`);
  console.error('Run with --dry-run to audit targets without modifying data.');
  console.error('================================================================');
  process.exit(1);
}

function isTargetUser(user) {
  const phone = user.phoneNumber ? user.phoneNumber.replace(/^\+91/, '').trim() : '';
  if (phone && DEMO_PHONES.includes(phone)) return true;

  const email = (user.email || '').toLowerCase().trim();
  if (
    email.endsWith('@test.com') ||
    email.endsWith('.demo@doctornect.com') ||
    email.endsWith('demo.@doctornect.com') ||
    email.startsWith('demo_') ||
    email.startsWith('test_')
  ) {
    return true;
  }

  const uid = user.uid || '';
  if (uid.startsWith('demo_') || uid.startsWith('fb_uid_') || uid.startsWith('test_')) {
    return true;
  }

  return false;
}

async function run() {
  console.log('================================================================');
  console.log('DOCTORNECT: FIREBASE AUTH & S3 TEST DATA PURGE');
  console.log(`MODE: ${isDryRun ? 'DRY-RUN (Audit only — zero mutations)' : '*** LIVE PURGE ***'}`);
  console.log(`TARGET DEMO PHONES: ${DEMO_PHONES.length > 0 ? DEMO_PHONES.join(', ') : '(None configured — matching test emails and synthetic UIDs only)'}`);
  console.log('================================================================\n');

  let targetUids = [];

  // --- Step 1: Firebase Auth Scan ---
  console.log('--- 1. FIREBASE AUTH USER SCAN ---');
  const hasGcpCredentials =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    process.env.FIREBASE_CONFIG ||
    process.env.GCLOUD_PROJECT ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST;

  if (!adminApp || !adminAuth) {
    console.log('NOTICE: firebase-admin module not available. Skipping Firebase Auth scan.');
  } else if (!hasGcpCredentials) {
    console.log('NOTICE: No GCP credentials, FIREBASE_CONFIG, or emulator set. Skipping Firebase Auth scan (set GOOGLE_APPLICATION_CREDENTIALS to run in staging/prod).');
  } else {
    try {
      const apps = adminApp.getApps();
      if (apps.length === 0) {
        adminApp.initializeApp();
      }
      const auth = adminAuth.getAuth();

      // List all users in batches
      let nextPageToken;
      let totalScanned = 0;
      do {
        const listResult = await auth.listUsers(1000, nextPageToken);
        totalScanned += listResult.users.length;
        for (const user of listResult.users) {
          if (isTargetUser(user)) {
            targetUids.push(user.uid);
            console.log(`  [Target Account] UID: ${user.uid} | Email: ${user.email || 'none'} | Phone: ${user.phoneNumber || 'none'}`);
          }
        }
        nextPageToken = listResult.pageToken;
      } while (nextPageToken);

      console.log(`Scanned ${totalScanned} Firebase Auth users. Found ${targetUids.length} test accounts.`);

      if (!isDryRun && targetUids.length > 0) {
        // Delete users in chunks of 1000
        for (let i = 0; i < targetUids.length; i += 1000) {
          const chunk = targetUids.slice(i, i + 1000);
          const delRes = await auth.deleteUsers(chunk);
          console.log(`  -> DELETED ${delRes.successCount} Firebase Auth users (failures: ${delRes.failureCount})`);
        }
      }
    } catch (e) {
      console.warn(`NOTICE: Firebase Admin initialization or listing skipped (${e.message}).`);
    }
  }

  // --- Step 2: S3 Object Scan & Deletion ---
  console.log('\n--- 2. S3 TEST USER OBJECT SCAN ---');
  const bucket = process.env.AWS_S3_BUCKET_NAME;
  if (!bucket || !S3Client) {
    console.log(`NOTICE: ${!bucket ? 'AWS_S3_BUCKET_NAME not set' : 'S3Client not available'}. Skipping S3 scan.`);
  } else {
    try {
      const s3 = new S3Client({
        region: process.env.AWS_REGION || 'ap-south-1',
        ...(process.env.AWS_ENDPOINT ? { endpoint: process.env.AWS_ENDPOINT, forcePathStyle: true } : {}),
      });

      const prefixesToScan = ['avatars/', 'prescriptions/', 'health-records/', 'lab-reports/', 'ad-banners/'];
      let totalS3Objects = 0;
      const s3KeysToDelete = [];

      for (const prefix of prefixesToScan) {
        let continuationToken;
        do {
          const listCmd = new ListObjectsV2Command({
            Bucket: bucket,
            Prefix: prefix,
            ContinuationToken: continuationToken,
          });
          const listRes = await s3.send(listCmd);
          if (listRes.Contents) {
            for (const obj of listRes.Contents) {
              // Check if object key belongs to one of targetUids or synthetic prefix
              const isMatch =
                targetUids.some((uid) => obj.Key.includes(uid)) ||
                obj.Key.includes('demo_') ||
                obj.Key.includes('test_');

              if (isMatch) {
                totalS3Objects++;
                s3KeysToDelete.push({ Key: obj.Key });
                console.log(`  [Target S3 Object] ${obj.Key} (${obj.Size} bytes)`);
              }
            }
          }
          continuationToken = listRes.NextContinuationToken;
        } while (continuationToken);
      }

      console.log(`Found ${totalS3Objects} test S3 objects in bucket ${bucket}.`);

      if (!isDryRun && s3KeysToDelete.length > 0) {
        for (let i = 0; i < s3KeysToDelete.length; i += 1000) {
          const batch = s3KeysToDelete.slice(i, i + 1000);
          const delCmd = new DeleteObjectsCommand({
            Bucket: bucket,
            Delete: { Objects: batch },
          });
          const delRes = await s3.send(delCmd);
          console.log(`  -> DELETED ${delRes.Deleted ? delRes.Deleted.length : 0} S3 objects.`);
        }
      }
    } catch (e) {
      console.warn(`NOTICE: S3 scan skipped (${e.message}).`);
    }
  }

  console.log('\n================================================================');
  if (isDryRun) {
    console.log('DRY-RUN COMPLETE: Zero Firebase Auth accounts or S3 objects were deleted.');
    console.log('To execute live purge, run with:');
    console.log(`  node backend/scripts/purge_firebase_test_users_and_s3.js --confirm-prod-purge=${REQUIRED_CONFIRM_TOKEN}`);
  } else {
    console.log('SUCCESS: Live purge completed for Firebase Auth test accounts and S3 objects.');
  }
  console.log('================================================================');
}

run().catch((err) => {
  console.error('Fatal error in purge_firebase_test_users_and_s3:', err);
  process.exit(1);
});
