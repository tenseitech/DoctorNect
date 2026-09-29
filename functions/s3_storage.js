'use strict';

const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { getFirestore } = require('firebase-admin/firestore');
const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { enforceAbuseLimit } = require('./abuse_rate_limit');

// Firebase Secret Manager declarations
const awsAccessKeyId = defineSecret('AWS_ACCESS_KEY_ID');
const awsSecretAccessKey = defineSecret('AWS_SECRET_ACCESS_KEY');

const CALLABLE_REGION = 'asia-south1';
const AWS_REGION = process.env.AWS_REGION || 'ap-south-1';
const S3_BUCKET = process.env.S3_BUCKET || 'doctornect';

const ENFORCE_ABUSE_APP_CHECK = String(
  process.env.ENFORCE_ABUSE_APP_CHECK || process.env.ENFORCE_OTP_APP_CHECK || 'true',
)
  .trim()
  .toLowerCase() !== 'false';

const SUPER_ADMIN_EMAILS = [
  'sharmasd2@gmail.com',
  'tenseitechpvtltd@gmail.com',
  'admin@doctornect.com',
  'superadmin@doctornect.com',
  'support@doctornect.com',
];

const ALLOWED_CONTENT_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/pdf',
]);

const IMAGE_ONLY_CONTENT_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
]);

const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // 5 MB
const MAX_DOC_BYTES = 15 * 1024 * 1024; // 15 MB

let _testingS3Client = null;

function setS3ClientForTesting(client) {
  _testingS3Client = client;
}

function getS3Client() {
  if (_testingS3Client) return _testingS3Client;

  const keyId =
    (typeof awsAccessKeyId?.value === 'function' ? awsAccessKeyId.value() : null) ||
    process.env.AWS_ACCESS_KEY_ID;
  const secretKey =
    (typeof awsSecretAccessKey?.value === 'function' ? awsSecretAccessKey.value() : null) ||
    process.env.AWS_SECRET_ACCESS_KEY;

  if (!keyId || !secretKey) {
    throw new HttpsError('failed-precondition', 'AWS S3 credentials are not configured.');
  }

  return new S3Client({
    region: AWS_REGION,
    credentials: {
      accessKeyId: keyId.trim(),
      secretAccessKey: secretKey.trim(),
    },
    requestChecksumCalculation: 'WHEN_REQUIRED',
    responseChecksumValidation: 'WHEN_REQUIRED',
  });
}

function requireAuth(request) {
  if (!request?.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }
}

function isSuperAdmin(auth, userDoc) {
  const email = String(auth?.token?.email || '').trim().toLowerCase();
  if (email && SUPER_ADMIN_EMAILS.includes(email)) return true;
  const role = userDoc?.role || '';
  return role === 'super_admin' || role === 'superAdmin' || role === 'admin';
}

function extractExtension(fileName, contentType) {
  const cleanName = String(fileName || '').trim().toLowerCase();
  const match = cleanName.match(/\.([a-z0-9]+)$/);
  if (match) {
    const ext = match[1];
    if (ext === 'jpeg' || ext === 'jpg') return 'jpg';
    if (ext === 'png') return 'png';
    if (ext === 'webp') return 'webp';
    if (ext === 'pdf') return 'pdf';
  }
  if (contentType === 'application/pdf') return 'pdf';
  if (contentType === 'image/png') return 'png';
  if (contentType === 'image/webp') return 'webp';
  return 'jpg';
}

/**
 * Validates contentType and sizeBytes against allowed limits.
 */
function validateContentTypeAndSize(purpose, contentType, sizeBytes) {
  if (!contentType || !ALLOWED_CONTENT_TYPES.has(contentType)) {
    throw new HttpsError(
      'invalid-argument',
      `Content-Type '${contentType}' is not allowed. Allowed types: image/jpeg, image/png, image/webp, application/pdf.`,
    );
  }

  const numBytes = Number(sizeBytes);
  if (!Number.isFinite(numBytes) || numBytes <= 0) {
    throw new HttpsError('invalid-argument', 'sizeBytes must be a positive integer.');
  }

  const isImagePurpose =
    purpose === 'patient_profile' ||
    purpose === 'patientPhoto' ||
    purpose === 'doctor_profile' ||
    purpose === 'doctorPhoto' ||
    purpose === 'promoted_ads' ||
    purpose === 'promotedAd';

  if (isImagePurpose) {
    if (!IMAGE_ONLY_CONTENT_TYPES.has(contentType)) {
      throw new HttpsError('invalid-argument', 'Profile photos and ad banners must be images (JPEG, PNG, WebP).');
    }
    if (numBytes > MAX_IMAGE_BYTES) {
      throw new HttpsError('invalid-argument', `File size exceeds the 5 MB limit (received ${(numBytes / (1024 * 1024)).toFixed(2)} MB).`);
    }
  } else {
    if (numBytes > MAX_DOC_BYTES) {
      throw new HttpsError('invalid-argument', `File size exceeds the 15 MB limit (received ${(numBytes / (1024 * 1024)).toFixed(2)} MB).`);
    }
  }
}

/**
 * Validates that an S3 object key does not contain path traversal tricks,
 * consecutive slashes, leading slashes, or unexpected characters.
 */
function isValidObjectKey(key) {
  if (typeof key !== 'string' || !key) return false;
  if (key.startsWith('/')) return false;
  if (key.includes('//')) return false;
  if (key.includes('..')) return false;
  if (key.includes('\\')) return false;
  // Allowed characters: letters, numbers, '.', '_', '-', '/'
  if (!/^[a-zA-Z0-9._/-]+$/.test(key)) return false;
  const segments = key.split('/');
  for (const seg of segments) {
    if (!seg || seg === '.' || seg === '..') return false;
  }
  return true;
}

function assertValidObjectKey(key, paramName = 'objectKey') {
  if (!isValidObjectKey(key)) {
    throw new HttpsError(
      'invalid-argument',
      `Invalid ${paramName}: path traversal ('..'), '//', leading '/', and special characters are not allowed.`,
    );
  }
}

/**
 * Checks if a key belongs to public-media purposes:
 * - patients/{id}/profile/...
 * - doctor_profiles/{id}/profile/...
 * - promoted_ads/...
 */
function isPublicMediaKey(key) {
  if (!isValidObjectKey(key)) return false;
  const parts = key.split('/');
  if (parts[0] === 'patients') {
    // patients/{id}/profile/{fileName}
    return parts.length >= 4 && parts[1].length > 0 && parts[2] === 'profile' && parts[3].length > 0;
  }
  if (parts[0] === 'doctor_profiles') {
    // doctor_profiles/{id}/profile/{fileName}
    return parts.length >= 4 && parts[1].length > 0 && parts[2] === 'profile' && parts[3].length > 0;
  }
  if (parts[0] === 'promoted_ads') {
    // promoted_ads/{providerId}/{adId}/{fileName} or promoted_ads/...
    return parts.length >= 3 && parts.every((p) => p.length > 0);
  }
  return false;
}

/**
 * Resolves caller profile from users/{uid}.
 */
async function resolveCallerUser(db, uid) {
  const userSnap = await db.collection('users').doc(uid).get();
  if (!userSnap.exists) {
    throw new HttpsError('unauthenticated', 'User profile document not found.');
  }
  return { id: userSnap.id, ...userSnap.data() };
}

/**
 * Normalizes purpose string.
 */
function normalizePurpose(raw) {
  const p = String(raw || '').trim();
  switch (p) {
    case 'health_records':
    case 'healthRecord':
    case 'health_record':
      return 'health_records';
    case 'lab_reports':
    case 'labReport':
    case 'lab_report':
      return 'lab_reports';
    case 'patient_profile':
    case 'patientPhoto':
    case 'patient_photo':
      return 'patient_profile';
    case 'doctor_profile':
    case 'doctorPhoto':
    case 'doctor_photo':
      return 'doctor_profile';
    case 'promoted_ads':
    case 'promotedAd':
    case 'promoted_ad':
    case 'ad_banner':
    case 'adBanner':
      return 'promoted_ads';
    default:
      return p;
  }
}

/**
 * 1. getS3UploadUrl core handler.
 */
async function getS3UploadUrlHandler(data, auth, db) {
  const purpose = normalizePurpose(data?.purpose);
  const parentId = String(data?.parentId || '').trim();
  const fileName = String(data?.fileName || '').trim();
  const contentType = String(data?.contentType || '').trim().toLowerCase();
  const sizeBytes = Number(data?.sizeBytes);

  if (!purpose) {
    throw new HttpsError('invalid-argument', 'purpose is required.');
  }
  if (!parentId) {
    throw new HttpsError('invalid-argument', 'parentId is required.');
  }
  if (!fileName) {
    throw new HttpsError('invalid-argument', 'fileName is required.');
  }

  assertValidObjectKey(parentId, 'parentId');
  if (
    fileName.includes('..') ||
    fileName.includes('/') ||
    fileName.includes('\\') ||
    !/^[a-zA-Z0-9._-]+$/.test(fileName)
  ) {
    throw new HttpsError(
      'invalid-argument',
      "Invalid fileName: path traversal ('..'), slashes, and special characters are not allowed.",
    );
  }

  validateContentTypeAndSize(purpose, contentType, sizeBytes);

  const caller = await resolveCallerUser(db, auth.uid);
  const isAdmin = isSuperAdmin(auth, caller);
  const uuid = crypto.randomUUID();
  const ext = extractExtension(fileName, contentType);

  let objectKey = '';

  switch (purpose) {
    case 'health_records': {
      // parentId can be 'recordId' or 'patientId/recordId'
      let patientId = caller.profileId || '';
      let recordId = parentId;
      if (parentId.includes('/')) {
        const parts = parentId.split('/');
        patientId = parts[0];
        recordId = parts[1];
      }

      if (!isAdmin) {
        if (caller.role !== 'patient' || caller.profileId !== patientId) {
          throw new HttpsError('permission-denied', 'Only the patient owner can upload health records.');
        }
        if (caller.profileCompleted === false) {
          throw new HttpsError('permission-denied', 'Please complete your patient profile before uploading records.');
        }
      }

      objectKey = `health_records/${patientId}/${recordId}/${uuid}.${ext}`;
      break;
    }

    case 'lab_reports': {
      // parentId can be 'bookingId' or 'patientId/bookingId'
      let bookingId = parentId;
      if (parentId.includes('/')) {
        bookingId = parentId.split('/')[1];
      }

      let patientId = '';
      if (!isAdmin) {
        if (caller.role !== 'lab') {
          throw new HttpsError('permission-denied', 'Only authorized diagnostic labs can upload lab reports.');
        }

        // Verify lab booking or lab order ownership
        let bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
        if (bookingDoc.exists) {
          const bookingData = bookingDoc.data();
          if (bookingData.status === 'cancelled') {
            throw new HttpsError('failed-precondition', 'Cannot upload report for a cancelled booking.');
          }
          if (bookingData.labId !== caller.profileId) {
            throw new HttpsError('permission-denied', 'This lab booking is not assigned to your laboratory.');
          }
          patientId = bookingData.patientId;
        } else {
          const orderDoc = await db.collection('lab_orders').doc(bookingId).get();
          if (orderDoc.exists) {
            const orderData = orderDoc.data();
            if (orderData.status === 'cancelled') {
              throw new HttpsError('failed-precondition', 'Cannot upload report for a cancelled lab order.');
            }
            if (orderData.labId !== caller.profileId) {
              throw new HttpsError('permission-denied', 'This lab order is not assigned to your laboratory.');
            }
            patientId = orderData.patientId;
          } else {
            throw new HttpsError('not-found', 'Lab booking or order not found.');
          }
        }
      } else {
        // Super admin upload: look up patientId from booking if exists, or fallback
        const bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
        patientId = bookingDoc.exists ? bookingDoc.data().patientId : (parentId.includes('/') ? parentId.split('/')[0] : 'admin');
      }

      objectKey = `lab_reports/${patientId}/${bookingId}/${uuid}.${ext}`;
      break;
    }

    case 'patient_profile': {
      const targetPatientId = parentId;
      if (!isAdmin) {
        if (caller.role !== 'patient' || caller.profileId !== targetPatientId) {
          throw new HttpsError('permission-denied', 'You can only upload your own profile photo.');
        }
      }
      objectKey = `patients/${targetPatientId}/profile/${uuid}.jpg`;
      break;
    }

    case 'doctor_profile': {
      const targetDoctorId = parentId;
      if (!isAdmin) {
        if (caller.role !== 'doctor' || caller.profileId !== targetDoctorId) {
          throw new HttpsError('permission-denied', 'You can only upload your own doctor profile photo.');
        }
      }
      objectKey = `doctor_profiles/${targetDoctorId}/profile/${uuid}.jpg`;
      break;
    }

    case 'promoted_ads': {
      const adId = parentId;
      const providerId = auth.uid;
      objectKey = `promoted_ads/${providerId}/${adId}/${uuid}.jpg`;
      break;
    }

    default:
      throw new HttpsError('invalid-argument', `Unknown storage purpose: '${purpose}'.`);
  }

  assertValidObjectKey(objectKey, 'objectKey');

  const s3 = getS3Client();
  const command = new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: objectKey,
    ContentType: contentType,
    ContentLength: sizeBytes,
  });

  const uploadUrl = await getSignedUrl(s3, command, {
    expiresIn: 300,
    signableHeaders: new Set(['content-type', 'content-length', 'host']),
  });

  return {
    uploadUrl,
    objectKey,
  };
}

/**
 * Authorizes read access to a given objectKey.
 */
async function authorizeRead(objectKey, caller, auth, db) {
  if (isSuperAdmin(auth, caller)) return true;

  const parts = objectKey.split('/');
  const prefix = parts[0];

  // Public profiles and promoted ads can be read by any authenticated user
  if (prefix === 'patients' || prefix === 'doctor_profiles' || prefix === 'promoted_ads') {
    return true;
  }

  if (prefix === 'health_records') {
    // health_records/{patientId}/{recordId}/{fileName}
    const patientId = parts[1];
    const recordId = parts[2];

    if (caller.role === 'patient' && caller.profileId === patientId) {
      return true;
    }

    if (caller.role === 'doctor') {
      // 1. Doctor must be admin-verified and not deactivated
      const doctorDoc = await db.collection('doctors').doc(caller.profileId || '').get();
      if (!doctorDoc.exists || doctorDoc.data()?.verified !== true || doctorDoc.data()?.deactivated === true) {
        return false;
      }

      // 2. Patient must allow record sharing
      const patientDoc = await db.collection('patients').doc(patientId).get();
      if (!patientDoc.exists) return false;
      const pData = patientDoc.data();
      if (pData.shareRecordsWithDoctors === false) return false;

      // 3. Doctor must have clinical care relationship
      const careTeam = Array.isArray(pData.careTeamDoctorIds) ? pData.careTeamDoctorIds : [];
      const isCareDoctor =
        careTeam.includes(caller.profileId) ||
        pData.primaryDoctorId === caller.profileId ||
        pData.invitedDoctorId === caller.profileId;

      if (!isCareDoctor) {
        // Also check if an active appointment links them
        const aptQuery = await db
          .collection('appointments')
          .where('patientId', '==', patientId)
          .where('doctorId', '==', caller.profileId)
          .limit(1)
          .get();
        if (aptQuery.empty) return false;
      }

      // 4. Record itself must have sharedWithDoctors == true (if record doc exists)
      const recordDoc = await db.collection('health_records').doc(recordId).get();
      if (recordDoc.exists && recordDoc.data()?.sharedWithDoctors === false) {
        return false;
      }

      return true;
    }

    return false;
  }

  if (prefix === 'lab_reports') {
    // lab_reports/{patientId}/{bookingId}/{fileName}
    const patientId = parts[1];
    const bookingId = parts[2];

    if (caller.role === 'patient' && caller.profileId === patientId) {
      return true;
    }

    if (caller.role === 'lab') {
      const bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
      if (bookingDoc.exists) {
        const bData = bookingDoc.data();
        if (bData.labId === caller.profileId && bData.status !== 'cancelled') {
          return true;
        }
      }
      const orderDoc = await db.collection('lab_orders').doc(bookingId).get();
      if (orderDoc.exists) {
        const oData = orderDoc.data();
        if (oData.labId === caller.profileId && oData.status !== 'cancelled') {
          return true;
        }
      }
      return false;
    }

    return false;
  }

  return false;
}

/**
 * Authorizes delete access to a given objectKey (owner-only or super admin).
 */
async function authorizeDelete(objectKey, caller, auth, db) {
  if (isSuperAdmin(auth, caller)) return true;

  const parts = objectKey.split('/');
  const prefix = parts[0];

  if (prefix === 'health_records') {
    // health_records/{patientId}/{recordId}/{fileName}
    const patientId = parts[1];
    return caller.role === 'patient' && caller.profileId === patientId;
  }

  if (prefix === 'lab_reports') {
    // lab_reports/{patientId}/{bookingId}/{fileName}
    const bookingId = parts[2];
    if (caller.role === 'lab') {
      const bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
      if (bookingDoc.exists && bookingDoc.data()?.labId === caller.profileId) {
        return true;
      }
      const orderDoc = await db.collection('lab_orders').doc(bookingId).get();
      if (orderDoc.exists && orderDoc.data()?.labId === caller.profileId) {
        return true;
      }
    }
    return false;
  }

  if (prefix === 'patients') {
    // patients/{patientId}/profile/{fileName}
    const patientId = parts[1];
    return caller.role === 'patient' && caller.profileId === patientId;
  }

  if (prefix === 'doctor_profiles') {
    // doctor_profiles/{doctorId}/profile/{fileName}
    const doctorId = parts[1];
    return caller.role === 'doctor' && caller.profileId === doctorId;
  }

  if (prefix === 'promoted_ads') {
    // promoted_ads/{providerId}/{adId}/{fileName}
    const providerId = parts[1];
    return auth.uid === providerId || caller.profileId === providerId;
  }

  return false;
}

/**
 * 2. getS3DownloadUrl core handler.
 */
async function getS3DownloadUrlHandler(data, auth, db) {
  const objectKey = String(data?.objectKey || '').trim();
  if (!objectKey) {
    throw new HttpsError('invalid-argument', 'objectKey is required.');
  }
  assertValidObjectKey(objectKey, 'objectKey');

  const caller = await resolveCallerUser(db, auth.uid);
  const allowed = await authorizeRead(objectKey, caller, auth, db);
  if (!allowed) {
    throw new HttpsError('permission-denied', 'You do not have permission to access this file.');
  }

  const s3 = getS3Client();
  const command = new GetObjectCommand({
    Bucket: S3_BUCKET,
    Key: objectKey,
  });

  const expiresIn = 600; // 10 minutes
  const url = await getSignedUrl(s3, command, { expiresIn });

  return {
    url,
    expiresIn,
  };
}

/**
 * 3. getS3DownloadUrls batch handler (max 20).
 * Accepts ONLY public-media keys:
 * - patients/{id}/profile/...
 * - doctor_profiles/{id}/profile/...
 * - promoted_ads/...
 * Rejects health_records/, lab_reports/, and unknown prefixes with invalid-argument for the WHOLE request.
 */
async function getS3DownloadUrlsHandler(data, auth, db) {
  const objectKeys = data?.objectKeys;
  if (!Array.isArray(objectKeys) || objectKeys.length === 0) {
    throw new HttpsError('invalid-argument', 'objectKeys must be a non-empty array.');
  }
  if (objectKeys.length > 20) {
    throw new HttpsError('invalid-argument', 'A maximum of 20 objectKeys can be requested at once.');
  }

  // Reject the WHOLE request if ANY key is invalid or not a public-media key
  for (const rawKey of objectKeys) {
    const key = typeof rawKey === 'string' ? rawKey.trim() : '';
    if (!key) {
      throw new HttpsError('invalid-argument', 'objectKeys cannot contain empty strings.');
    }
    assertValidObjectKey(key, 'objectKeys item');
    if (!isPublicMediaKey(key)) {
      throw new HttpsError(
        'invalid-argument',
        `Invalid key '${key}': getS3DownloadUrls only accepts public-media keys (patients/{id}/profile/, doctor_profiles/{id}/profile/, promoted_ads/). Clinical and unknown prefixes are rejected.`,
      );
    }
  }

  const caller = await resolveCallerUser(db, auth.uid);
  const s3 = getS3Client();
  const urls = {};
  const expiresIn = 3600; // 1 hour for batch media

  for (const rawKey of objectKeys) {
    const key = String(rawKey || '').trim();

    const allowed = await authorizeRead(key, caller, auth, db);
    if (!allowed) continue;

    const command = new GetObjectCommand({
      Bucket: S3_BUCKET,
      Key: key,
    });
    try {
      urls[key] = await getSignedUrl(s3, command, { expiresIn });
    } catch (_) {
      // Omit failed keys from response map
    }
  }

  return { urls };
}

/**
 * 4. deleteS3Object core handler.
 */
async function deleteS3ObjectHandler(data, auth, db) {
  const objectKey = String(data?.objectKey || '').trim();
  if (!objectKey) {
    throw new HttpsError('invalid-argument', 'objectKey is required.');
  }
  assertValidObjectKey(objectKey, 'objectKey');

  const caller = await resolveCallerUser(db, auth.uid);
  const allowed = await authorizeDelete(objectKey, caller, auth, db);
  if (!allowed) {
    throw new HttpsError('permission-denied', 'You do not have permission to delete this file.');
  }

  const s3 = getS3Client();
  await s3.send(
    new DeleteObjectCommand({
      Bucket: S3_BUCKET,
      Key: objectKey,
    }),
  );

  return {
    success: true,
    objectKey,
  };
}

// ----------------------------------------------------------------------------
// EXPORTED CLOUD FUNCTIONS (Callable v2, asia-south1, with secrets & abuse guard)
// ----------------------------------------------------------------------------

const CALLABLE_OPTIONS = {
  region: CALLABLE_REGION,
  secrets: [awsAccessKeyId, awsSecretAccessKey],
  enforceAppCheck: ENFORCE_ABUSE_APP_CHECK,
};

exports.getS3UploadUrl = onCall(CALLABLE_OPTIONS, async (request) => {
  requireAuth(request);
  const db = getFirestore();
  await enforceAbuseLimit(db, request, 'api');
  return getS3UploadUrlHandler(request.data, request.auth, db);
});

exports.getS3DownloadUrl = onCall(CALLABLE_OPTIONS, async (request) => {
  requireAuth(request);
  const db = getFirestore();
  await enforceAbuseLimit(db, request, 'api');
  return getS3DownloadUrlHandler(request.data, request.auth, db);
});

exports.getS3DownloadUrls = onCall(CALLABLE_OPTIONS, async (request) => {
  requireAuth(request);
  const db = getFirestore();
  await enforceAbuseLimit(db, request, 'api');
  return getS3DownloadUrlsHandler(request.data, request.auth, db);
});

exports.deleteS3Object = onCall(CALLABLE_OPTIONS, async (request) => {
  requireAuth(request);
  const db = getFirestore();
  await enforceAbuseLimit(db, request, 'api');
  return deleteS3ObjectHandler(request.data, request.auth, db);
});

// Export handlers & testing helpers for unit tests
exports._test = {
  getS3UploadUrlHandler,
  getS3DownloadUrlHandler,
  getS3DownloadUrlsHandler,
  deleteS3ObjectHandler,
  setS3ClientForTesting,
  validateContentTypeAndSize,
  extractExtension,
  authorizeRead,
  authorizeDelete,
  isSuperAdmin,
  isValidObjectKey,
  assertValidObjectKey,
  isPublicMediaKey,
};
