'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { _test } = require('../s3_storage');

const {
  getS3UploadUrlHandler,
  getS3DownloadUrlHandler,
  getS3DownloadUrlsHandler,
  deleteS3ObjectHandler,
  setS3ClientForTesting,
  validateContentTypeAndSize,
  extractExtension,
} = _test;

/**
 * In-memory Mock Firestore for unit testing authorization matrix.
 */
function createMockDb(initialData = {}) {
  const store = new Map();

  for (const [coll, docs] of Object.entries(initialData)) {
    for (const [id, data] of Object.entries(docs)) {
      store.set(`${coll}/${id}`, data);
    }
  }

  return {
    collection(collName) {
      return {
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
function createMockS3Client() {
  const client = new S3Client({
    region: 'ap-south-1',
    credentials: {
      accessKeyId: 'mock-access-key',
      secretAccessKey: 'mock-secret-key',
    },
    requestChecksumCalculation: 'WHEN_REQUIRED',
    responseChecksumValidation: 'WHEN_REQUIRED',
  });
  client.send = async () => ({});
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
  assert.equal(res.expiresIn, 600);
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
  assert.equal(res.expiresIn, 600);
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

  const auth = { uid: 'uid_admin', token: { email: 'admin@doctornect.com' } };
  const data = { objectKey: 'health_records/p_99/hr_99/secret.pdf' };

  const res = await getS3DownloadUrlHandler(data, auth, db);
  assert.ok(res.url);
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

test('batch download resolves signed URLs for public profile photos', async () => {
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
