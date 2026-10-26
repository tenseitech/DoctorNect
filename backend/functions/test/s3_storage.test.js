'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { _test } = require('../s3_storage');

const {
  getS3UploadUrlHandler,
  getS3DownloadUrlHandler,
  getS3DownloadUrlsHandler,
  deleteS3ObjectHandler,
  confirmS3UploadHandler,
  logStorageAccess,
  setS3ClientForTesting,
  validateContentTypeAndSize,
  extractExtension,
} = _test;

const { _resetRemoteConfigCache } = require('../sync_flags');

let origEnvCutover;
let origServiceKey;
test.beforeEach(() => {
  origEnvCutover = process.env.USE_SUPABASE_DB_DOCTOR_PATIENT;
  origServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = '0';
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'dummy-service-role-key-for-test';
  }
  _resetRemoteConfigCache();
});

test.afterEach(() => {
  if (origEnvCutover === undefined) delete process.env.USE_SUPABASE_DB_DOCTOR_PATIENT;
  else process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = origEnvCutover;

  if (origServiceKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  else process.env.SUPABASE_SERVICE_ROLE_KEY = origServiceKey;

  _resetRemoteConfigCache();
});

/**
 * In-memory Mock Firestore for unit testing authorization matrix.
 */
function createMockDb(initialData = {}) {
  const store = new Map();
  const added = [];

  for (const [coll, docs] of Object.entries(initialData)) {
    for (const [id, data] of Object.entries(docs)) {
      store.set(`${coll}/${id}`, data);
    }
  }

  return {
    _store: store,
    _added: added,
    collection(collName) {
      return {
        async add(data) {
          const autoId = `auto_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
          const key = `${collName}/${autoId}`;
          store.set(key, data);
          added.push({ collection: collName, id: autoId, data });
          return { id: autoId };
        },
        doc(docId) {
          const key = `${collName}/${docId}`;
          return {
            async get() {
              const data = store.get(key);
              return {
                id: docId,
                exists: data !== undefined,
                data: () => data || null,
              };
            },
            async set(data, options = {}) {
              if (options.merge) {
                const existing = store.get(key) || {};
                store.set(key, { ...existing, ...data });
              } else {
                store.set(key, { ...data });
              }
            },
            async update(data) {
              const existing = store.get(key) || {};
              store.set(key, { ...existing, ...data });
            },
            async delete() {
              store.delete(key);
            },
          };
        },
        where(field, op, val) {
          return {
            where(field2, op2, val2) {
              return {
                limit(n) {
                  return {
                    async get() {
                      const matches = [];
                      for (const [k, d] of store.entries()) {
                        if (k.startsWith(`${collName}/`)) {
                          if (d[field] === val && d[field2] === val2) {
                            matches.push({ id: k.split('/')[1], data: () => d });
                          }
                        }
                      }
                      return {
                        empty: matches.length === 0,
                        docs: matches.slice(0, n),
                      };
                    },
                  };
                },
              };
            },
            limit(n) {
              return {
                async get() {
                  const matches = [];
                  for (const [k, d] of store.entries()) {
                    if (k.startsWith(`${collName}/`) && d[field] === val) {
                      matches.push({ id: k.split('/')[1], data: () => d });
                    }
                  }
                  return {
                    empty: matches.length === 0,
                    docs: matches.slice(0, n),
                  };
                },
              };
            },
          };
        },
      };
    },
  };
}

const { S3Client } = require('@aws-sdk/client-s3');

/**
 * Mock S3 Client with mock credentials for local SigV4 presigning without network calls.
 */
function createMockS3Client(mockHead = null) {
  const client = new S3Client({
    region: 'ap-south-1',
    credentials: {
      accessKeyId: 'mock-access-key',
      secretAccessKey: 'mock-secret-key',
    },
    requestChecksumCalculation: 'WHEN_REQUIRED',
    responseChecksumValidation: 'WHEN_REQUIRED',
  });
  client.send = async (cmd) => {
    if (cmd && cmd.constructor && cmd.constructor.name === 'HeadObjectCommand') {
      if (typeof mockHead === 'function') {
        return mockHead(cmd);
      }
      return mockHead || { ContentType: 'application/pdf', ContentLength: 2048 };
    }
    return {};
  };
  return client;
}

test.beforeEach(() => {
  setS3ClientForTesting(createMockS3Client());
});

// ----------------------------------------------------------------------------
// 1. EXTENSION & CONTENT-TYPE EXTRACTION
// ----------------------------------------------------------------------------
test('extractExtension normalizes correctly', () => {
  assert.equal(extractExtension('test.pdf', 'application/pdf'), 'pdf');
  assert.equal(extractExtension('photo.JPEG', 'image/jpeg'), 'jpg');
  assert.equal(extractExtension('scan.PNG', 'image/png'), 'png');
  assert.equal(extractExtension('banner.webp', 'image/webp'), 'webp');
  assert.equal(extractExtension('file_no_ext', 'application/pdf'), 'pdf');
});

// ----------------------------------------------------------------------------
// 2. CONTENT TYPE & SIZE ALLOWLIST
// ----------------------------------------------------------------------------
test('validateContentTypeAndSize rejects unsupported content types', () => {
  assert.throws(
    () => validateContentTypeAndSize('health_records', 'application/x-sh', 1024),
    /Content-Type 'application\/x-sh' is not allowed/,
  );
  assert.throws(
    () => validateContentTypeAndSize('health_records', 'text/html', 1024),
    /Content-Type 'text\/html' is not allowed/,
  );
});

test('validateContentTypeAndSize rejects PDF for profile photos and ad banners', () => {
  assert.throws(
    () => validateContentTypeAndSize('patient_profile', 'application/pdf', 1024),
    /must be images/,
  );
  assert.throws(
    () => validateContentTypeAndSize('doctor_profile', 'application/pdf', 1024),
    /must be images/,
  );
  assert.throws(
    () => validateContentTypeAndSize('promoted_ads', 'application/pdf', 1024),
    /must be images/,
  );
});

test('validateContentTypeAndSize rejects oversized files', () => {
  // Photos > 5 MB
  assert.throws(
    () => validateContentTypeAndSize('patient_profile', 'image/jpeg', 6 * 1024 * 1024),
    /exceeds the 5 MB limit/,
  );
  // Docs > 15 MB
  assert.throws(
    () => validateContentTypeAndSize('health_records', 'application/pdf', 16 * 1024 * 1024),
    /exceeds the 15 MB limit/,
  );
  // Zero or negative bytes
  assert.throws(
    () => validateContentTypeAndSize('health_records', 'application/pdf', 0),
    /sizeBytes must be a positive integer/,
  );
});

// ----------------------------------------------------------------------------
// 3. UPLOAD AUTHORIZATION MATRIX
// ----------------------------------------------------------------------------
test('wrong patient blocked from uploading to another patient record', async () => {
  const db = createMockDb({
    users: {
      uid_patient_1: { role: 'patient', profileId: 'p_1', profileCompleted: true },
    },
  });

  const auth = { uid: 'uid_patient_1' };
  const data = {
    purpose: 'health_records',
    parentId: 'p_2/hr_100', // Attempting to write into p_2
    fileName: 'prescription.pdf',
    contentType: 'application/pdf',
    sizeBytes: 1024,
  };

  await assert.rejects(
    async () => getS3UploadUrlHandler(data, auth, db),
    /Only the patient owner can upload health records/,
  );
});

test('pharmacy, lab, and ambulance owners can upload their own KYC and nobody else can', async () => {
  const db = createMockDb({
    users: {
      uid_store: { role: 'medicalStore', profileId: 'store_1' },
      uid_lab: { role: 'lab', profileId: 'lab_1' },
      uid_amb: { role: 'ambulance', profileId: 'amb_1' },
      uid_patient: { role: 'patient', profileId: 'p_1', profileCompleted: true },
    },
  });

  const pharmacy = await getS3UploadUrlHandler({
    purpose: 'pharmacy_kyc',
    parentId: 'store_1',
    fileName: 'license.pdf',
    contentType: 'application/pdf',
    sizeBytes: 2048,
  }, { uid: 'uid_store' }, db);
  assert.ok(pharmacy.objectKey.startsWith('pharmacies/store_1/documents/'));

  const lab = await getS3UploadUrlHandler({
    purpose: 'lab_kyc',
    parentId: 'lab_1',
    fileName: 'nabl.pdf',
    contentType: 'application/pdf',
    sizeBytes: 2048,
  }, { uid: 'uid_lab' }, db);
  assert.ok(lab.objectKey.startsWith('labs/lab_1/documents/'));

  const ambulance = await getS3UploadUrlHandler({
    purpose: 'ambulance_kyc',
    parentId: 'amb_1',
    fileName: 'permit.pdf',
    contentType: 'application/pdf',
    sizeBytes: 2048,
  }, { uid: 'uid_amb' }, db);
  assert.ok(ambulance.objectKey.startsWith('ambulances/amb_1/documents/'));

  await assert.rejects(
    () => getS3UploadUrlHandler({
      purpose: 'pharmacy_kyc',
      parentId: 'store_1',
      fileName: 'license.pdf',
      contentType: 'application/pdf',
      sizeBytes: 2048,
    }, { uid: 'uid_patient' }, db),
    /Only the pharmacy owner can upload pharmacy KYC/,
  );

  const { authorizeRead } = _test;
  const owner = { role: 'medicalStore', profileId: 'store_1' };
  assert.equal(
    await authorizeRead(pharmacy.objectKey, owner, { uid: 'uid_store' }, db),
    false,
  );
});

test('patient owner allowed to upload health record', async () => {
  const db = createMockDb({
    users: {
      uid_patient_1: { role: 'patient', profileId: 'p_1', profileCompleted: true },
    },
  });

  const auth = { uid: 'uid_patient_1' };
  const data = {
    purpose: 'health_records',
    parentId: 'hr_100',
    fileName: 'prescription.pdf',
    contentType: 'application/pdf',
    sizeBytes: 1024,
  };

  const res = await getS3UploadUrlHandler(data, auth, db);
  assert.ok(res.objectKey.startsWith('health_records/p_1/hr_100/'));
  assert.ok(res.objectKey.endsWith('.pdf'));
  assert.ok(res.uploadUrl);
  // Presigned PUT size & type enforcement: content-length and content-type MUST be in signed headers
  assert.match(res.uploadUrl, /X-Amz-SignedHeaders=[^&]*content-length/i);
  assert.match(res.uploadUrl, /X-Amz-SignedHeaders=[^&]*content-type/i);
  // Checksum params must be completely absent from URL
  assert.doesNotMatch(res.uploadUrl.toLowerCase(), /checksum/);
});

test('presigned PUT URL enforces Content-Length signature and excludes checksum params', async () => {
  const db = createMockDb({
    users: {
      uid_patient_1: { role: 'patient', profileId: 'p_1', profileCompleted: true },
    },
  });

  const auth = { uid: 'uid_patient_1' };
  const data = {
    purpose: 'health_records',
    parentId: 'hr_500',
    fileName: 'scan.png',
    contentType: 'image/png',
    sizeBytes: 2048576, // ~2 MB
  };

  const res = await getS3UploadUrlHandler(data, auth, db);
  const parsedUrl = new URL(res.uploadUrl);
  const signedHeaders = parsedUrl.searchParams.get('X-Amz-SignedHeaders') || '';

  // 1. Assert content-length is present in signed headers
  assert.ok(
    signedHeaders.split(';').includes('content-length'),
    `Expected 'content-length' in X-Amz-SignedHeaders, got: ${signedHeaders}`,
  );

  // 2. Assert content-type is present in signed headers
  assert.ok(
    signedHeaders.split(';').includes('content-type'),
    `Expected 'content-type' in X-Amz-SignedHeaders, got: ${signedHeaders}`,
  );

  // 3. Assert no checksum parameter exists in the URL query string
  for (const param of parsedUrl.searchParams.keys()) {
    assert.doesNotMatch(
      param.toLowerCase(),
      /checksum/,
      `Unexpected checksum parameter found in presigned PUT URL: ${param}`,
    );
  }
});

test('wrong lab blocked from uploading report for another lab booking', async () => {
  const db = createMockDb({
    users: {
      uid_lab_1: { role: 'lab', profileId: 'lab_1', profileCompleted: true },
    },
    lab_bookings: {
      booking_100: {
        patientId: 'p_1',
        labId: 'lab_2', // Assigned to lab_2!
        status: 'sampleCollected',
      },
    },
  });

  const auth = { uid: 'uid_lab_1' };
  const data = {
    purpose: 'lab_reports',
    parentId: 'booking_100',
    fileName: 'cbc_report.pdf',
    contentType: 'application/pdf',
    sizeBytes: 2048,
  };

  await assert.rejects(
    async () => getS3UploadUrlHandler(data, auth, db),
    /This lab booking is not assigned to your laboratory/,
  );
});

test('cancelled lab booking upload is rejected', async () => {
  const db = createMockDb({
    users: {
      uid_lab_1: { role: 'lab', profileId: 'lab_1', profileCompleted: true },
    },
    lab_bookings: {
      booking_cancelled: {
        patientId: 'p_1',
        labId: 'lab_1',
        status: 'cancelled',
      },
    },
  });

  const auth = { uid: 'uid_lab_1' };
  const data = {
    purpose: 'lab_reports',
    parentId: 'booking_cancelled',
    fileName: 'cbc_report.pdf',
    contentType: 'application/pdf',
    sizeBytes: 2048,
  };

  await assert.rejects(
    async () => getS3UploadUrlHandler(data, auth, db),
    /Cannot upload report for a cancelled booking/,
  );
});

test('assigned lab allowed to upload report', async () => {
  const db = createMockDb({
    users: {
      uid_lab_1: { role: 'lab', profileId: 'lab_1', profileCompleted: true },
    },
    lab_bookings: {
      booking_valid: {
        patientId: 'p_55',
        labId: 'lab_1',
        status: 'inAnalysis',
      },
    },
  });

  const auth = { uid: 'uid_lab_1' };
  const data = {
    purpose: 'lab_reports',
    parentId: 'booking_valid',
    fileName: 'thyroid.pdf',
    contentType: 'application/pdf',
    sizeBytes: 4096,
  };

  const res = await getS3UploadUrlHandler(data, auth, db);
  assert.ok(res.objectKey.startsWith('lab_reports/p_55/booking_valid/'));
  assert.ok(res.objectKey.endsWith('.pdf'));
});

// ----------------------------------------------------------------------------
// 4. DOWNLOAD AUTHORIZATION MATRIX
// ----------------------------------------------------------------------------
test('doctor without patient sharing blocked from downloading health record', async () => {
  const db = createMockDb({
    users: {
      uid_doctor_1: { role: 'doctor', profileId: 'doc_1' },
    },
    doctors: {
      doc_1: { verified: true, deactivated: false },
    },
    patients: {
      p_1: {
        shareRecordsWithDoctors: false, // Patient opted out of sharing
        careTeamDoctorIds: ['doc_1'],
      },
    },
    health_records: {
      hr_1: { sharedWithDoctors: true },
    },
  });

  const auth = { uid: 'uid_doctor_1' };
  const data = { objectKey: 'health_records/p_1/hr_1/file123.pdf' };

  await assert.rejects(
    async () => getS3DownloadUrlHandler(data, auth, db),
    /You do not have permission to access this file/,
  );
});

test('unverified doctor blocked from downloading health record', async () => {
  const db = createMockDb({
    users: {
      uid_doctor_unverified: { role: 'doctor', profileId: 'doc_unverified' },
    },
    doctors: {
      doc_unverified: { verified: false }, // Not verified
    },
    patients: {
      p_1: {
        shareRecordsWithDoctors: true,
        careTeamDoctorIds: ['doc_unverified'],
      },
    },
    health_records: {
      hr_1: { sharedWithDoctors: true },
    },
  });

  const auth = { uid: 'uid_doctor_unverified' };
  const data = { objectKey: 'health_records/p_1/hr_1/file123.pdf' };

  await assert.rejects(
    async () => getS3DownloadUrlHandler(data, auth, db),
    /You do not have permission to access this file/,
  );
});

test('verified doctor with care relationship allowed to download shared record', async () => {
  const db = createMockDb({
    users: {
      uid_doctor_ok: { role: 'doctor', profileId: 'doc_ok' },
    },
    doctors: {
      doc_ok: { verified: true, deactivated: false },
    },
    patients: {
      p_1: {
        shareRecordsWithDoctors: true,
        careTeamDoctorIds: ['doc_ok'],
      },
    },
    health_records: {
      hr_1: { sharedWithDoctors: true },
    },
  });

  const auth = { uid: 'uid_doctor_ok' };
  const data = { objectKey: 'health_records/p_1/hr_1/file123.pdf' };

  const res = await getS3DownloadUrlHandler(data, auth, db);
  assert.equal(res.expiresIn, 300);
  assert.ok(res.url);
});

test('patient owner allowed to download their own health record', async () => {
  const db = createMockDb({
    users: {
      uid_p1: { role: 'patient', profileId: 'p_1' },
    },
  });

  const auth = { uid: 'uid_p1' };
  const data = { objectKey: 'health_records/p_1/hr_1/uuid123.pdf' };

  const res = await getS3DownloadUrlHandler(data, auth, db);
  assert.equal(res.expiresIn, 300);
  assert.ok(res.url);
});

test('different patient blocked from downloading health record', async () => {
  const db = createMockDb({
    users: {
      uid_p2: { role: 'patient', profileId: 'p_2' },
    },
  });

  const auth = { uid: 'uid_p2' };
  const data = { objectKey: 'health_records/p_1/hr_1/uuid123.pdf' };

  await assert.rejects(
    async () => getS3DownloadUrlHandler(data, auth, db),
    /You do not have permission to access this file/,
  );
});

test('super admin bypass allows downloading any file', async () => {
  const db = createMockDb({
    users: {
      uid_admin: { role: 'super_admin', profileId: 'admin_1' },
    },
  });

  const auth = { uid: 'uid_admin', token: { email: 'admin@doctornect.com', email_verified: true } };
  const data = { objectKey: 'health_records/p_99/hr_99/secret.pdf' };

  const res = await getS3DownloadUrlHandler(data, auth, db);
  assert.ok(res.url);
});

test('super admin allowlisted email with email_verified=false is denied admin bypass', async () => {
  const db = createMockDb({
    users: {
      uid_unverified: { role: 'patient', profileId: 'p_unverified' },
    },
  });

  const auth = { uid: 'uid_unverified', token: { email: 'admin@doctornect.com', email_verified: false } };
  const data = { objectKey: 'health_records/p_99/hr_99/secret.pdf' };

  await assert.rejects(
    async () => getS3DownloadUrlHandler(data, auth, db),
    /You do not have permission to access this file/,
  );
});

test('claim-based admin bypass allows download regardless of non-allowlisted email when email_verified=true', async () => {
  const db = createMockDb({
    users: {
      uid_claim_admin: { role: 'admin', profileId: 'adm_001' },
    },
  });

  const auth = {
    uid: 'uid_claim_admin',
    token: {
      email: 'custom_ops_staff@external-domain.org',
      email_verified: true,
      user_role: 'admin',
    },
  };
  const data = { objectKey: 'health_records/p_99/hr_99/secret.pdf' };

  const res = await getS3DownloadUrlHandler(data, auth, db);
  assert.ok(res.url);
});

test('claim-based admin bypass is denied when email_verified=false', async () => {
  const db = createMockDb({
    users: {
      uid_claim_unverified: { role: 'admin', profileId: 'adm_002' },
    },
  });

  const auth = {
    uid: 'uid_claim_unverified',
    token: {
      email: 'custom_ops_staff@external-domain.org',
      email_verified: false,
      user_role: 'admin',
    },
  };
  const data = { objectKey: 'health_records/p_99/hr_99/secret.pdf' };

  await assert.rejects(
    async () => getS3DownloadUrlHandler(data, auth, db),
    /You do not have permission to access this file/,
  );
});

// ----------------------------------------------------------------------------
// 5. BATCH DOWNLOAD (getS3DownloadUrls)
// ----------------------------------------------------------------------------
test('batch download caps at 20 keys', async () => {
  const db = createMockDb({
    users: { uid_user: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'uid_user' };
  const keys = Array.from({ length: 21 }, (_, i) => `patients/p_1/profile/${i}.jpg`);

  await assert.rejects(
    async () => getS3DownloadUrlsHandler({ objectKeys: keys }, auth, db),
    /maximum of 20 objectKeys/,
  );
});

test('batch download resolves signed URLs for public profile photos and banners', async () => {
  const db = createMockDb({
    users: { uid_user: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'uid_user' };
  const keys = [
    'patients/p_1/profile/1.jpg',
    'doctor_profiles/d_1/profile/2.jpg',
    'promoted_ads/prov_1/ad_1/3.jpg',
  ];

  const res = await getS3DownloadUrlsHandler({ objectKeys: keys }, auth, db);
  assert.equal(Object.keys(res.urls).length, 3);
  assert.ok(res.urls['patients/p_1/profile/1.jpg']);
  assert.ok(res.urls['doctor_profiles/d_1/profile/2.jpg']);
  assert.ok(res.urls['promoted_ads/prov_1/ad_1/3.jpg']);
});

test('batch download rejects health_records key with invalid-argument', async () => {
  const db = createMockDb({
    users: { uid_user: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'uid_user' };
  const keys = ['health_records/p_1/hr_1/file.pdf'];

  await assert.rejects(
    async () => getS3DownloadUrlsHandler({ objectKeys: keys }, auth, db),
    /only accepts public-media keys/,
  );
});

test('batch download rejects lab_reports key with invalid-argument', async () => {
  const db = createMockDb({
    users: { uid_user: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'uid_user' };
  const keys = ['lab_reports/p_1/bk_1/file.pdf'];

  await assert.rejects(
    async () => getS3DownloadUrlsHandler({ objectKeys: keys }, auth, db),
    /only accepts public-media keys/,
  );
});

test('batch download rejects mixed batch entirely', async () => {
  const db = createMockDb({
    users: { uid_user: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'uid_user' };
  const keys = [
    'patients/p_1/profile/1.jpg',
    'health_records/p_1/hr_1/file.pdf',
  ];

  await assert.rejects(
    async () => getS3DownloadUrlsHandler({ objectKeys: keys }, auth, db),
    /only accepts public-media keys/,
  );
});

test('batch download rejects path traversal key', async () => {
  const db = createMockDb({
    users: { uid_user: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'uid_user' };
  const keys = ['patients/p_1/profile/../../secret.txt'];

  await assert.rejects(
    async () => getS3DownloadUrlsHandler({ objectKeys: keys }, auth, db),
    /path traversal/,
  );
});

test('endpoints reject path traversal, leading slashes, and double slashes', async () => {
  const db = createMockDb({
    users: { uid_p1: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'uid_p1' };

  // getS3DownloadUrl
  await assert.rejects(
    async () => getS3DownloadUrlHandler({ objectKey: '../health_records/p_1/1.pdf' }, auth, db),
    /path traversal/,
  );
  await assert.rejects(
    async () => getS3DownloadUrlHandler({ objectKey: '/patients/p_1/profile/1.jpg' }, auth, db),
    /path traversal/,
  );
  await assert.rejects(
    async () => getS3DownloadUrlHandler({ objectKey: 'patients//p_1/profile/1.jpg' }, auth, db),
    /path traversal/,
  );

  // deleteS3Object
  await assert.rejects(
    async () => deleteS3ObjectHandler({ objectKey: 'patients/p_1/../other/1.jpg' }, auth, db),
    /path traversal/,
  );

  // getS3UploadUrl with invalid parentId or fileName
  await assert.rejects(
    async () =>
      getS3UploadUrlHandler(
        {
          purpose: 'patient_profile',
          parentId: '../p_1',
          fileName: 'avatar.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 1024,
        },
        auth,
        db,
      ),
    /path traversal/,
  );
  await assert.rejects(
    async () =>
      getS3UploadUrlHandler(
        {
          purpose: 'patient_profile',
          parentId: 'p_1',
          fileName: '../../avatar.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 1024,
        },
        auth,
        db,
      ),
    /path traversal/,
  );
});

// ----------------------------------------------------------------------------
// 6. DELETE AUTHORIZATION (deleteS3Object)
// ----------------------------------------------------------------------------
test('non-owner blocked from deleting health record', async () => {
  const db = createMockDb({
    users: { uid_p2: { role: 'patient', profileId: 'p_2' } },
  });
  const auth = { uid: 'uid_p2' };
  const data = { objectKey: 'health_records/p_1/hr_1/file.pdf' };

  await assert.rejects(
    async () => deleteS3ObjectHandler(data, auth, db),
    /You do not have permission to delete this file/,
  );
});

test('patient owner allowed to delete their health record', async () => {
  const db = createMockDb({
    users: { uid_p1: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'uid_p1' };
  const data = { objectKey: 'health_records/p_1/hr_1/file.pdf' };

  const res = await deleteS3ObjectHandler(data, auth, db);
  assert.equal(res.success, true);
  assert.equal(res.objectKey, 'health_records/p_1/hr_1/file.pdf');
});

// ----------------------------------------------------------------------------
// 7. UNAUTHENTICATED REJECTION
// ----------------------------------------------------------------------------
test('unauthenticated call rejected on upload and download', async () => {
  const db = createMockDb({});
  const unauth = null;

  await assert.rejects(
    async () => getS3UploadUrlHandler({ purpose: 'health_records', parentId: 'hr1', fileName: 'f.pdf', contentType: 'application/pdf', sizeBytes: 100 }, unauth, db),
    /User profile document not found|unauthenticated|Cannot read properties of null/,
  );

  await assert.rejects(
    async () => getS3DownloadUrlHandler({ objectKey: 'health_records/p1/hr1/f.pdf' }, unauth, db),
    /User profile document not found|unauthenticated|Cannot read properties of null/,
  );
});

// ----------------------------------------------------------------------------
// 8. LAB ORDERS — UPLOAD AUTHORIZATION
// ----------------------------------------------------------------------------
test('assigned lab allowed to upload report for lab_order via parentId "{patientId}/{orderId}"', async () => {
  const db = createMockDb({
    users: {
      uid_lab_1: { role: 'lab', profileId: 'lab_1', profileCompleted: true },
    },
    lab_orders: {
      order_200: {
        patientId: 'p_42',
        doctorId: 'doc_7',
        labId: 'lab_1',
        status: 'in_progress',
      },
    },
  });

  const auth = { uid: 'uid_lab_1' };
  const data = {
    purpose: 'lab_reports',
    parentId: 'p_42/order_200',
    fileName: 'cbc_report.pdf',
    contentType: 'application/pdf',
    sizeBytes: 4096,
  };

  const res = await getS3UploadUrlHandler(data, auth, db);
  assert.ok(res.objectKey.startsWith('lab_reports/p_42/order_200/'));
  assert.ok(res.objectKey.endsWith('.pdf'));
  assert.ok(res.uploadUrl);
});

test('wrong lab blocked from uploading report for lab_order', async () => {
  const db = createMockDb({
    users: {
      uid_lab_1: { role: 'lab', profileId: 'lab_1', profileCompleted: true },
    },
    lab_orders: {
      order_201: {
        patientId: 'p_42',
        doctorId: 'doc_7',
        labId: 'lab_99', // Assigned to lab_99, not lab_1
        status: 'in_progress',
      },
    },
  });

  const auth = { uid: 'uid_lab_1' };
  const data = {
    purpose: 'lab_reports',
    parentId: 'p_42/order_201',
    fileName: 'report.pdf',
    contentType: 'application/pdf',
    sizeBytes: 2048,
  };

  await assert.rejects(
    async () => getS3UploadUrlHandler(data, auth, db),
    /This lab order is not assigned to your laboratory/,
  );
});

test('cancelled lab_order upload is rejected', async () => {
  const db = createMockDb({
    users: {
      uid_lab_1: { role: 'lab', profileId: 'lab_1', profileCompleted: true },
    },
    lab_orders: {
      order_cancelled: {
        patientId: 'p_42',
        doctorId: 'doc_7',
        labId: 'lab_1',
        status: 'cancelled',
      },
    },
  });

  const auth = { uid: 'uid_lab_1' };
  const data = {
    purpose: 'lab_reports',
    parentId: 'p_42/order_cancelled',
    fileName: 'report.pdf',
    contentType: 'application/pdf',
    sizeBytes: 2048,
  };

  await assert.rejects(
    async () => getS3UploadUrlHandler(data, auth, db),
    /Cannot upload report for a cancelled lab order/,
  );
});

// ----------------------------------------------------------------------------
// 9. LAB ORDERS — DOWNLOAD AUTHORIZATION
// ----------------------------------------------------------------------------
test('patient owner allowed to download lab_order report', async () => {
  const db = createMockDb({
    users: {
      uid_p42: { role: 'patient', profileId: 'p_42' },
    },
  });

  const auth = { uid: 'uid_p42' };
  const data = { objectKey: 'lab_reports/p_42/order_200/uuid123.pdf' };

  const res = await getS3DownloadUrlHandler(data, auth, db);
  assert.ok(res.url);
  assert.equal(res.expiresIn, 300);
});

test('unrelated patient blocked from downloading lab_order report', async () => {
  const db = createMockDb({
    users: {
      uid_p99: { role: 'patient', profileId: 'p_99' },
    },
  });

  const auth = { uid: 'uid_p99' };
  const data = { objectKey: 'lab_reports/p_42/order_200/uuid123.pdf' };

  await assert.rejects(
    async () => getS3DownloadUrlHandler(data, auth, db),
    /You do not have permission to access this file/,
  );
});

test('unrelated doctor blocked from downloading lab_order report', async () => {
  const db = createMockDb({
    users: {
      uid_doc_1: { role: 'doctor', profileId: 'doc_1' },
    },
  });

  const auth = { uid: 'uid_doc_1' };
  const data = { objectKey: 'lab_reports/p_42/order_200/uuid123.pdf' };

  await assert.rejects(
    async () => getS3DownloadUrlHandler(data, auth, db),
    /You do not have permission to access this file/,
  );
});

test('assigned lab allowed to download lab_order report', async () => {
  const db = createMockDb({
    users: {
      uid_lab_1: { role: 'lab', profileId: 'lab_1' },
    },
    lab_orders: {
      order_200: {
        patientId: 'p_42',
        doctorId: 'doc_7',
        labId: 'lab_1',
        status: 'completed',
      },
    },
  });

  const auth = { uid: 'uid_lab_1' };
  const data = { objectKey: 'lab_reports/p_42/order_200/uuid123.pdf' };

  const res = await getS3DownloadUrlHandler(data, auth, db);
  assert.ok(res.url);
});

test('wrong lab blocked from downloading lab_order report', async () => {
  const db = createMockDb({
    users: {
      uid_lab_wrong: { role: 'lab', profileId: 'lab_wrong' },
    },
    lab_orders: {
      order_200: {
        patientId: 'p_42',
        doctorId: 'doc_7',
        labId: 'lab_1', // Assigned to lab_1, not lab_wrong
        status: 'completed',
      },
    },
  });

  const auth = { uid: 'uid_lab_wrong' };
  const data = { objectKey: 'lab_reports/p_42/order_200/uuid123.pdf' };

  await assert.rejects(
    async () => getS3DownloadUrlHandler(data, auth, db),
    /You do not have permission to access this file/,
  );
});

// ----------------------------------------------------------------------------
// 10. LAB ORDERS — DELETE AUTHORIZATION
// ----------------------------------------------------------------------------
test('assigned lab allowed to delete lab_order report', async () => {
  const db = createMockDb({
    users: {
      uid_lab_1: { role: 'lab', profileId: 'lab_1' },
    },
    lab_orders: {
      order_200: {
        patientId: 'p_42',
        doctorId: 'doc_7',
        labId: 'lab_1',
        status: 'completed',
      },
    },
  });

  const auth = { uid: 'uid_lab_1' };
  const data = { objectKey: 'lab_reports/p_42/order_200/uuid123.pdf' };

  const res = await deleteS3ObjectHandler(data, auth, db);
  assert.equal(res.success, true);
});

test('wrong lab blocked from deleting lab_order report', async () => {
  const db = createMockDb({
    users: {
      uid_lab_wrong: { role: 'lab', profileId: 'lab_wrong' },
    },
    lab_orders: {
      order_200: {
        patientId: 'p_42',
        doctorId: 'doc_7',
        labId: 'lab_1',
        status: 'completed',
      },
    },
  });

  const auth = { uid: 'uid_lab_wrong' };
  const data = { objectKey: 'lab_reports/p_42/order_200/uuid123.pdf' };

  await assert.rejects(
    async () => deleteS3ObjectHandler(data, auth, db),
    /You do not have permission to delete this file/,
  );
});

// ----------------------------------------------------------------------------
// 10. CONFIRM S3 UPLOAD (Step 3: HeadObject verification & DB persistence)
// ----------------------------------------------------------------------------
test('confirmS3Upload verifies S3 HeadObject and persists s3_key in DB', async () => {
  const db = createMockDb({
    users: {
      uid_p1: { role: 'patient', profileId: 'p_1' },
    },
    health_records: {
      rec_1: { title: 'Blood Report' },
    },
  });

  // Configure mock S3 client with valid HeadObject response
  setS3ClientForTesting(createMockS3Client({
    ContentType: 'application/pdf',
    ContentLength: 4096,
  }));

  const auth = { uid: 'uid_p1' };
  const data = {
    objectKey: 'health_records/p_1/rec_1/uuid123.pdf',
    purpose: 'health_records',
    recordId: 'rec_1',
  };

  const res = await confirmS3UploadHandler(data, auth, db);
  assert.equal(res.success, true);
  assert.equal(res.contentLength, 4096);
  assert.equal(res.contentType, 'application/pdf');

  // Verify DB record was updated with S3 metadata
  const doc = await db.collection('health_records').doc('rec_1').get();
  assert.equal(doc.data().s3Key, 'health_records/p_1/rec_1/uuid123.pdf');
  assert.equal(doc.data().fileSizeBytes, 4096);
  assert.equal(doc.data().mimeType, 'application/pdf');
  assert.equal(doc.data().storageProvider, 's3');
  assert.ok(doc.data().uploadConfirmedAt);
});

test('confirmS3Upload rejects when caller is not the owner (403)', async () => {
  const db = createMockDb({
    users: {
      uid_p2: { role: 'patient', profileId: 'p_2' },
    },
  });

  const auth = { uid: 'uid_p2' };
  const data = {
    objectKey: 'health_records/p_1/rec_1/uuid123.pdf',
    purpose: 'health_records',
    recordId: 'rec_1',
  };

  await assert.rejects(
    async () => confirmS3UploadHandler(data, auth, db),
    /You do not have permission to confirm this upload/,
  );
});

test('confirmS3Upload rejects when S3 HeadObject throws not-found (404)', async () => {
  const db = createMockDb({
    users: {
      uid_p1: { role: 'patient', profileId: 'p_1' },
    },
  });

  // Mock S3 client where HeadObject throws NoSuchKey
  const client = createMockS3Client();
  client.send = async (cmd) => {
    if (cmd?.constructor?.name === 'HeadObjectCommand') {
      const err = new Error('NotFound');
      err.name = 'NotFound';
      throw err;
    }
    return {};
  };
  setS3ClientForTesting(client);

  const auth = { uid: 'uid_p1' };
  const data = {
    objectKey: 'health_records/p_1/rec_1/uuid123.pdf',
    purpose: 'health_records',
    recordId: 'rec_1',
  };

  await assert.rejects(
    async () => confirmS3UploadHandler(data, auth, db),
    /Uploaded file was not found in S3/,
  );
});

test('confirmS3Upload rejects when S3 HeadObject size exceeds limit', async () => {
  const db = createMockDb({
    users: {
      uid_p1: { role: 'patient', profileId: 'p_1' },
    },
  });

  // Mock S3 client where file size is 25 MB (exceeds 15 MB doc limit)
  setS3ClientForTesting(createMockS3Client({
    ContentType: 'application/pdf',
    ContentLength: 25 * 1024 * 1024,
  }));

  const auth = { uid: 'uid_p1' };
  const data = {
    objectKey: 'health_records/p_1/rec_1/uuid123.pdf',
    purpose: 'health_records',
    recordId: 'rec_1',
  };

  await assert.rejects(
    async () => confirmS3UploadHandler(data, auth, db),
    /exceeds limit/,
  );
});

test('confirmS3Upload rejects invalid Content-Type in S3 HeadObject', async () => {
  const db = createMockDb({
    users: {
      uid_p1: { role: 'patient', profileId: 'p_1' },
    },
  });

  // Mock S3 client with unallowed mime type
  setS3ClientForTesting(createMockS3Client({
    ContentType: 'application/x-executable',
    ContentLength: 1024,
  }));

  const auth = { uid: 'uid_p1' };
  const data = {
    objectKey: 'health_records/p_1/rec_1/uuid123.exe',
    purpose: 'health_records',
    recordId: 'rec_1',
  };

  await assert.rejects(
    async () => confirmS3UploadHandler(data, auth, db),
    /Invalid S3 object Content-Type/,
  );
});

// ----------------------------------------------------------------------------
// 11. AUDIT LOGGING (Step 3: storage_audit_logs verification)
// ----------------------------------------------------------------------------
test('storage operations record immutable rows in storage_audit_logs', async () => {
  const db = createMockDb({
    users: {
      uid_p1: { role: 'patient', profileId: 'p_1', profileCompleted: true },
    },
    health_records: {
      rec_1: {},
    },
  });

  setS3ClientForTesting(createMockS3Client({
    ContentType: 'application/pdf',
    ContentLength: 1024,
  }));

  const auth = { uid: 'uid_p1' };

  // 1. Upload presigned
  const uploadRes = await getS3UploadUrlHandler({
    purpose: 'health_records',
    parentId: 'p_1/rec_1',
    fileName: 'lab_scan.pdf',
    contentType: 'application/pdf',
    sizeBytes: 1024,
  }, auth, db);
  assert.ok(uploadRes.uploadUrl);

  // 2. Download presigned
  const dlRes = await getS3DownloadUrlHandler({
    objectKey: uploadRes.objectKey,
  }, auth, db);
  assert.ok(dlRes.url);

  // 3. Confirm upload
  await confirmS3UploadHandler({
    objectKey: uploadRes.objectKey,
    purpose: 'health_records',
    recordId: 'rec_1',
  }, auth, db);

  // 4. Delete object
  await deleteS3ObjectHandler({
    objectKey: uploadRes.objectKey,
  }, auth, db);

  // Verify all 4 audit log entries were recorded
  const auditLogs = db._added.filter(entry => entry.collection === 'storage_audit_logs');
  assert.ok(auditLogs.length >= 4, `Expected at least 4 audit logs, got ${auditLogs.length}`);

  const actions = auditLogs.map(l => l.data.action);
  assert.ok(actions.includes('upload_presigned'));
  assert.ok(actions.includes('download_presigned'));
  assert.ok(actions.includes('upload_confirmed'));
  assert.ok(actions.includes('delete'));

  for (const log of auditLogs) {
    assert.equal(log.data.who, 'uid_p1');
    assert.equal(log.data.role, 'patient');
    assert.equal(log.data.status, 'success');
    assert.ok(log.data.when);
  }
});

// ----------------------------------------------------------------------------
// 12. PRESCRIPTIONS ACCESS CONTROL (Step 3: doctor, patient, assigned pharmacy)
// ----------------------------------------------------------------------------
test('prescriptions: patient owner allowed to download prescription', async () => {
  const db = createMockDb({
    users: {
      uid_p1: { role: 'patient', profileId: 'p_1' },
    },
  });

  const auth = { uid: 'uid_p1' };
  const data = { objectKey: 'prescriptions/p_1/rx_100/file.pdf' };

  const res = await getS3DownloadUrlHandler(data, auth, db);
  assert.ok(res.url);
  assert.equal(res.expiresIn, 300);
});

test('prescriptions: author doctor allowed to download prescription', async () => {
  const db = createMockDb({
    users: {
      uid_doc1: { role: 'doctor', profileId: 'doc_1' },
    },
    prescriptions: {
      rx_100: { doctorId: 'doc_1', patientId: 'p_1' },
    },
  });

  const auth = { uid: 'uid_doc1' };
  const data = { objectKey: 'prescriptions/p_1/rx_100/file.pdf' };

  const res = await getS3DownloadUrlHandler(data, auth, db);
  assert.ok(res.url);
  assert.equal(res.expiresIn, 300);
});

test('prescriptions: assigned pharmacy allowed to download prescription', async () => {
  const db = createMockDb({
    users: {
      uid_store1: { role: 'medicalStore', profileId: 'store_1' },
    },
    pharmacy_deliveries: {
      del_1: { prescriptionId: 'rx_100', storeId: 'store_1' },
    },
  });

  const auth = { uid: 'uid_store1' };
  const data = { objectKey: 'prescriptions/p_1/rx_100/file.pdf' };

  const res = await getS3DownloadUrlHandler(data, auth, db);
  assert.ok(res.url);
  assert.equal(res.expiresIn, 300);
});

test('prescriptions: unrelated pharmacy blocked from downloading prescription (403)', async () => {
  const db = createMockDb({
    users: {
      uid_store2: { role: 'medicalStore', profileId: 'store_2' },
    },
    pharmacy_deliveries: {
      del_1: { prescriptionId: 'rx_100', storeId: 'store_other' },
    },
  });

  const auth = { uid: 'uid_store2' };
  const data = { objectKey: 'prescriptions/p_1/rx_100/file.pdf' };

  await assert.rejects(
    async () => getS3DownloadUrlHandler(data, auth, db),
    /You do not have permission to access this file/,
  );
});

// ----------------------------------------------------------------------------
// 13. SUPABASE-PRIMARY DUAL-TARGET S3 AUTHORIZATION & AUDIT (Cutover Flag ON)
// ----------------------------------------------------------------------------

function createMockSupabase(initialTables = {}) {
  const tables = {};
  for (const [tbl, rows] of Object.entries(initialTables)) {
    tables[tbl] = Array.isArray(rows) ? rows.map(r => ({ ...r })) : [{ ...rows }];
  }
  const inserted = [];
  const updated = [];

  return {
    _tables: tables,
    _inserted: inserted,
    _updated: updated,
    from(tableName) {
      let currentRows = tables[tableName] || [];
      let pendingUpdate = null;
      let filterFn = () => true;

      const builder = {
        select(cols) {
          return builder;
        },
        eq(col, val) {
          const prev = filterFn;
          filterFn = (r) => prev(r) && String(r[col]) === String(val);
          return builder;
        },
        or(condition) {
          const prev = filterFn;
          filterFn = (r) => {
            if (!prev(r)) return false;
            const parts = condition.split(',');
            return parts.some((p) => {
              const [c, op, v] = p.split('.');
              return op === 'eq' && String(r[c]) === String(v);
            });
          };
          return builder;
        },
        limit(n) {
          return builder;
        },
        async maybeSingle() {
          const matching = currentRows.filter(filterFn);
          return { data: matching[0] || null, error: null };
        },
        async single() {
          const matching = currentRows.filter(filterFn);
          return { data: matching[0] || null, error: matching[0] ? null : new Error('Row not found') };
        },
        async insert(payload) {
          const row = { ...payload };
          if (!tables[tableName]) tables[tableName] = [];
          tables[tableName].push(row);
          inserted.push({ table: tableName, row });
          return { data: row, error: null };
        },
        update(payload) {
          pendingUpdate = payload;
          return {
            eq(col, val) {
              const matching = currentRows.filter(r => String(r[col]) === String(val));
              for (const r of matching) {
                Object.assign(r, pendingUpdate);
                updated.push({ table: tableName, row: r, patch: pendingUpdate });
              }
              return Promise.resolve({ data: matching, error: null });
            },
          };
        },
      };
      return builder;
    },
  };
}

test('S3 Supabase Primary: verified doctor with appointment reads patient record and logs to Postgres storage_audit_logs', async () => {
  const mockDb = createMockDb();
  const mockSupabase = createMockSupabase({
    users: [
      { id: 'uid_doc1', role: 'doctor', profile_id: 'doc_1', email: 'doc1@example.com' },
    ],
    doctors: [
      { doctor_id: 'doc_1', verified: true, deactivated: false },
    ],
    patients: [
      { patient_id: 'pat_1', share_records_with_doctors: true },
    ],
    appointments: [
      { appointment_id: 'apt_1', patient_id: 'pat_1', doctor_id: 'doc_1' },
    ],
    health_records: [
      { record_id: 'rec_10', shared_with_doctors: true },
    ],
  });

  const auth = { uid: 'uid_doc1' };
  const data = { objectKey: 'health_records/pat_1/rec_10/scan.pdf' };
  const storageOptions = {
    db: mockDb,
    supabaseClient: mockSupabase,
    isSupabasePrimary: true,
  };

  const res = await getS3DownloadUrlHandler(data, auth, storageOptions);
  assert.ok(res.url);

  // Verify audit log was written to Supabase storage_audit_logs table, NOT Firestore
  assert.equal(mockDb._added.length, 0);
  assert.equal(mockSupabase._inserted.length, 1);
  assert.equal(mockSupabase._inserted[0].table, 'storage_audit_logs');
  assert.equal(mockSupabase._inserted[0].row.who, 'uid_doc1');
  assert.equal(mockSupabase._inserted[0].row.action, 'download_presigned');
  assert.equal(mockSupabase._inserted[0].row.status, 'success');
});

test('S3 Supabase Primary: unverified doctor blocked from reading record even with appointment', async () => {
  const mockDb = createMockDb();
  const mockSupabase = createMockSupabase({
    users: [
      { id: 'uid_doc_unver', role: 'doctor', profile_id: 'doc_unver', email: 'unver@example.com' },
    ],
    doctors: [
      { doctor_id: 'doc_unver', verified: false, deactivated: false },
    ],
    patients: [
      { patient_id: 'pat_1', share_records_with_doctors: true },
    ],
    appointments: [
      { appointment_id: 'apt_1', patient_id: 'pat_1', doctor_id: 'doc_unver' },
    ],
  });

  const auth = { uid: 'uid_doc_unver' };
  const data = { objectKey: 'health_records/pat_1/rec_10/scan.pdf' };
  const storageOptions = {
    db: mockDb,
    supabaseClient: mockSupabase,
    isSupabasePrimary: true,
  };

  await assert.rejects(
    async () => getS3DownloadUrlHandler(data, auth, storageOptions),
    /You do not have permission to access this file/,
  );
});

test('S3 Supabase Primary: assigned lab allowed to upload/download lab report', async () => {
  const mockDb = createMockDb();
  const mockSupabase = createMockSupabase({
    users: [
      { id: 'uid_lab1', role: 'lab', profile_id: 'lab_1', email: 'lab@example.com' },
    ],
    lab_bookings: [
      { booking_id: 'b_100', lab_id: 'lab_1', status: 'confirmed' },
    ],
  });

  const auth = { uid: 'uid_lab1' };
  const storageOptions = {
    db: mockDb,
    supabaseClient: mockSupabase,
    isSupabasePrimary: true,
  };

  // 1. Upload URL
  const uploadRes = await getS3UploadUrlHandler({
    purpose: 'lab_reports',
    fileName: 'report.pdf',
    contentType: 'application/pdf',
    sizeBytes: 1024 * 1024,
    parentId: 'pat_1/b_100',
  }, auth, storageOptions);
  assert.ok(uploadRes.uploadUrl);

  // 2. Download URL
  const dlRes = await getS3DownloadUrlHandler({
    objectKey: 'lab_reports/pat_1/b_100/report.pdf',
  }, auth, storageOptions);
  assert.ok(dlRes.url);
});

test('S3 Supabase Primary: confirmS3Upload writes snake_case columns to Supabase and logs to Postgres', async () => {
  const mockDb = createMockDb();
  const mockSupabase = createMockSupabase({
    users: [
      { id: 'uid_pat1', role: 'patient', profile_id: 'pat_1' },
    ],
    health_records: [
      { record_id: 'rec_99', patient_id: 'pat_1' },
    ],
  });

  const auth = { uid: 'uid_pat1' };
  const storageOptions = {
    db: mockDb,
    supabaseClient: mockSupabase,
    isSupabasePrimary: true,
  };

  const confirmRes = await confirmS3UploadHandler({
    objectKey: 'health_records/pat_1/rec_99/blood_test.pdf',
    purpose: 'health_records',
    recordId: 'rec_99',
  }, auth, storageOptions);

  assert.equal(confirmRes.success, true);
  assert.equal(confirmRes.contentType, 'application/pdf');

  // Verify Supabase health_records row was updated with snake_case columns
  const updatedRows = mockSupabase._updated.filter(u => u.table === 'health_records');
  assert.equal(updatedRows.length, 1);
  const patch = updatedRows[0].patch;
  assert.equal(patch.s3_key, 'health_records/pat_1/rec_99/blood_test.pdf');
  assert.equal(patch.storage_provider, 's3');
  assert.equal(patch.file_size_bytes, 2048);
  assert.equal(patch.mime_type, 'application/pdf');
  assert.ok(patch.upload_confirmed_at);

  // Verify audit log went to Supabase storage_audit_logs table
  assert.equal(mockDb._added.length, 0);
  assert.equal(mockSupabase._inserted.length, 1);
  assert.equal(mockSupabase._inserted[0].table, 'storage_audit_logs');
  assert.equal(mockSupabase._inserted[0].row.action, 'upload_confirmed');
});

// ----------------------------------------------------------------------------
// 14. CONFIRM S3 UPLOAD FAILED VALIDATION: S3 OBJECT DELETION & AUDIT LOGGING
// ----------------------------------------------------------------------------

test('confirmS3Upload: missing object (head_not_found) attempts delete and audit logs failure', async () => {
  const mockDb = createMockDb({
    users: {
      uid_pat1: { role: 'patient', profileId: 'pat_1' },
    },
  });

  let deletedKey = null;
  setS3ClientForTesting({
    async send(cmd) {
      if (cmd.constructor.name === 'HeadObjectCommand') {
        const err = new Error('The specified key does not exist.');
        err.name = 'NotFound';
        throw err;
      }
      if (cmd.constructor.name === 'DeleteObjectCommand') {
        deletedKey = cmd.input.Key;
        return {};
      }
      return {};
    },
  });

  const auth = { uid: 'uid_pat1' };
  const targetKey = 'health_records/pat_1/rec_1/nonexistent.pdf';

  await assert.rejects(
    async () => confirmS3UploadHandler({
      objectKey: targetKey,
      purpose: 'health_records',
      recordId: 'rec_1',
    }, auth, mockDb),
    /Uploaded file was not found in S3 or is inaccessible/,
  );

  // Verify delete was sent for the failed object
  assert.equal(deletedKey, targetKey);

  // Verify failure was logged to storage_audit_logs
  const auditLogs = mockDb._added.filter(e => e.collection === 'storage_audit_logs');
  assert.equal(auditLogs.length, 1);
  assert.equal(auditLogs[0].data.action, 'upload_confirm_failed');
  assert.equal(auditLogs[0].data.status, 'head_not_found');
});

test('confirmS3Upload: invalid content-type deletes uploaded S3 object and audit logs failure', async () => {
  const mockDb = createMockDb({
    users: {
      uid_pat1: { role: 'patient', profileId: 'pat_1' },
    },
  });

  let deletedKey = null;
  setS3ClientForTesting({
    async send(cmd) {
      if (cmd.constructor.name === 'HeadObjectCommand') {
        return {
          ContentType: 'application/x-sh', // disallowed script
          ContentLength: 1024,
        };
      }
      if (cmd.constructor.name === 'DeleteObjectCommand') {
        deletedKey = cmd.input.Key;
        return {};
      }
      return {};
    },
  });

  const auth = { uid: 'uid_pat1' };
  const targetKey = 'health_records/pat_1/rec_1/malicious.sh';

  await assert.rejects(
    async () => confirmS3UploadHandler({
      objectKey: targetKey,
      purpose: 'health_records',
      recordId: 'rec_1',
    }, auth, mockDb),
    /Invalid S3 object Content-Type/,
  );

  assert.equal(deletedKey, targetKey);

  const auditLogs = mockDb._added.filter(e => e.collection === 'storage_audit_logs');
  assert.equal(auditLogs.length, 1);
  assert.equal(auditLogs[0].data.action, 'upload_confirm_failed');
  assert.equal(auditLogs[0].data.status, 'invalid_content_type');
});

test('confirmS3Upload: size exceeded deletes uploaded S3 object and audit logs failure', async () => {
  const mockDb = createMockDb({
    users: {
      uid_pat1: { role: 'patient', profileId: 'pat_1' },
    },
  });

  let deletedKey = null;
  setS3ClientForTesting({
    async send(cmd) {
      if (cmd.constructor.name === 'HeadObjectCommand') {
        return {
          ContentType: 'image/png',
          ContentLength: 20 * 1024 * 1024, // 20MB exceeds 5MB image limit
        };
      }
      if (cmd.constructor.name === 'DeleteObjectCommand') {
        deletedKey = cmd.input.Key;
        return {};
      }
      return {};
    },
  });

  const auth = { uid: 'uid_pat1' };
  const targetKey = 'patients/pat_1/profile/huge_photo.png';

  await assert.rejects(
    async () => confirmS3UploadHandler({
      objectKey: targetKey,
      purpose: 'patient_profile',
      recordId: 'pat_1',
    }, auth, mockDb),
    /exceeds limit/,
  );

  assert.equal(deletedKey, targetKey);

  const auditLogs = mockDb._added.filter(e => e.collection === 'storage_audit_logs');
  assert.equal(auditLogs.length, 1);
  assert.equal(auditLogs[0].data.action, 'upload_confirm_failed');
  assert.equal(auditLogs[0].data.status, 'size_exceeded');
});


