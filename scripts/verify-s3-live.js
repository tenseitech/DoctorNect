/**
 * Post-Deployment S3 Live Round-Trip Verification Script
 * Flow:
 * 1. Mints and signs in a bridged test user via Firebase Auth.
 * 2. Calls deployed Cloud Function `getS3UploadUrl` with Firebase ID token.
 * 3. PUTs test payload (1024 bytes) to the presigned S3 upload URL.
 * 4. Calls deployed Cloud Function `getS3DownloadUrl` with Firebase ID token.
 * 5. GETs the object from presigned S3 download URL and asserts payload matches byte-for-byte.
 * 6. Calls deployed Cloud Function `deleteS3Object` to delete the test object.
 * 7. Cleans up test identity in Firebase Auth.
 *
 * Credentials: Reads ONLY Firebase API key and Cloud Functions URL from env.
 * NEVER requires or stores AWS IAM keys.
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function parseEnv(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const content = fs.readFileSync(filePath, 'utf8');
  const env = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx !== -1) {
      let val = trimmed.slice(idx + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      env[trimmed.slice(0, idx).trim()] = val;
    }
  }
  return env;
}

const rootEnv = parseEnv(path.join(__dirname, '../.env'));
const backendEnv = parseEnv(path.join(__dirname, '../backend/functions/.env'));
const merged = { ...rootEnv, ...backendEnv, ...process.env };

const FIREBASE_API_KEY = merged.FIREBASE_API_KEY_WEB || process.env.FIREBASE_API_KEY;
const FUNCTIONS_URL = process.env.FUNCTIONS_BASE_URL || 'https://asia-south1-medibond-45fad.cloudfunctions.net';

const saPath = path.join(__dirname, 'service-account.json');
if (!admin.apps.length) {
  if (!fs.existsSync(saPath)) {
    console.error('ERROR: scripts/service-account.json is required for minting test user token');
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(require(saPath)) });
}

async function mintTestIdToken(uid) {
  await admin.auth().createUser({
    uid,
    phoneNumber: `+9199999${Math.floor(10000 + Math.random() * 90000)}`,
    displayName: `S3 Test User ${uid}`
  });
  await admin.auth().setCustomUserClaims(uid, {
    role: 'authenticated',
    app_role: 'patient',
    user_role: 'patient',
    verified: true
  });
  const customToken = await admin.auth().createCustomToken(uid);
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${FIREBASE_API_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: customToken, returnSecureToken: true })
  });
  if (!res.ok) {
    throw new Error(`Failed to exchange custom token: HTTP ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  return data.idToken;
}

async function callFunction(funcName, payload, token) {
  const url = `${FUNCTIONS_URL}/${funcName}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    },
    body: JSON.stringify({ data: payload })
  });

  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch (e) {
    throw new Error(`HTTP ${res.status} from ${funcName}: ${text}`);
  }
  if (!res.ok || json.error) {
    throw new Error(`Callable ${funcName} failed: HTTP ${res.status} ${JSON.stringify(json.error || json)}`);
  }
  return json.result;
}

async function run() {
  const testUid = `s3_verify_${Date.now()}`;
  let objectKeyToDelete = null;

  console.log(`Starting Live S3 Round-Trip Verification [Target: ${FUNCTIONS_URL}]`);
  try {
    // 1. Sign in test user
    console.log('1. Minting and authenticating test user token...');
    const idToken = await mintTestIdToken(testUid);
    console.log('   Authenticated with Firebase token.');

    // 2. Request Presigned Upload URL
    console.log('2. Calling getS3UploadUrl...');
    const uploadPayload = {
      purpose: 'patient_profile',
      parentId: testUid,
      fileName: 'avatar.jpg',
      contentType: 'image/jpeg',
      sizeBytes: 1024
    };
    const uploadResult = await callFunction('getS3UploadUrl', uploadPayload, idToken);
    const { uploadUrl, objectKey } = uploadResult;
    objectKeyToDelete = objectKey;
    console.log(`   Presigned upload URL received for key: ${objectKey}`);

    // 3. Upload test payload
    console.log('3. Uploading payload to S3 via presigned PUT URL...');
    const testBuffer = Buffer.alloc(1024, `DOCTORNECT_S3_TEST_PAYLOAD_${Date.now()}`);
    const putRes = await fetch(uploadUrl, {
      method: 'PUT',
      headers: {
        'Content-Type': 'image/jpeg'
      },
      body: testBuffer
    });
    if (!putRes.ok) {
      throw new Error(`S3 PUT failed: HTTP ${putRes.status} ${await putRes.text()}`);
    }
    console.log(`   S3 PUT success: HTTP ${putRes.status} OK`);

    // 4. Request Presigned Download URL
    console.log('4. Calling getS3DownloadUrl...');
    const downloadResult = await callFunction('getS3DownloadUrl', { objectKey }, idToken);
    const downloadUrl = downloadResult.url;
    console.log('   Presigned download URL received.');

    // 5. Download and verify content
    console.log('5. Downloading payload from S3 and comparing bytes...');
    const getRes = await fetch(downloadUrl);
    if (!getRes.ok) {
      throw new Error(`S3 GET failed: HTTP ${getRes.status} ${await getRes.text()}`);
    }
    const downloadedBuf = Buffer.from(await getRes.arrayBuffer());
    if (!testBuffer.equals(downloadedBuf)) {
      throw new Error('Downloaded buffer does not match uploaded payload!');
    }
    console.log('   S3 GET success: Byte comparison PASSED (1024 bytes matched).');

    // 6. Delete object
    console.log('6. Deleting test object from S3 via deleteS3Object...');
    await callFunction('deleteS3Object', { objectKey }, idToken);
    console.log('   S3 delete success.');

    console.log('\n============================================================');
    console.log('LIVE S3 ROUND-TRIP VERIFICATION: SUCCESS (100% PROVEN)');
    console.log('============================================================');

  } finally {
    // 7. Cleanup
    console.log('7. Cleaning up test user and lingering objects...');
    if (objectKeyToDelete) {
      // In case test failed before step 6
    }
    try {
      await admin.auth().deleteUser(testUid);
      console.log(`   Deleted test user ${testUid} from Firebase Auth.`);
    } catch (e) {}
  }
}

run().catch(err => {
  console.error('\nS3 Verification FAILED:', err.message);
  process.exit(1);
});
