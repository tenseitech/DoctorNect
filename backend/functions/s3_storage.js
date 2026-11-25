'use strict';

const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  DeleteObjectCommand,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { enforceAbuseLimit } = require('./abuse_rate_limit');
const { redisKey: envRedisKey } = require('./src/config/redis_keys');

// Firebase Secret Manager declarations
const awsAccessKeyId = defineSecret('AWS_ACCESS_KEY_ID');
const awsSecretAccessKey = defineSecret('AWS_SECRET_ACCESS_KEY');
const supabaseServiceRoleKey = defineSecret('SUPABASE_SERVICE_ROLE_KEY');

const { resolveS3Bucket } = require('./src/config/s3_bucket');

const CALLABLE_REGION = 'asia-south1';
const AWS_REGION = process.env.AWS_REGION || 'ap-south-1';
function s3Bucket() {
  return resolveS3Bucket();
}

const ENFORCE_ABUSE_APP_CHECK = String(
  process.env.ENFORCE_ABUSE_APP_CHECK || process.env.ENFORCE_OTP_APP_CHECK || 'true',
)
  .trim()
  .toLowerCase() !== 'false';

// Super admin = verified email in SUPER_ADMIN_EMAILS + admin custom claim (lib/super_admin.js).
const { isSuperAdmin } = require('./lib/super_admin');

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

let _testingSupabaseClient = null;

function setSupabaseClientForTesting(client) {
  _testingSupabaseClient = client;
}

function getSupabaseAdminClient(firebaseUid = null) {
  if (_testingSupabaseClient) return _testingSupabaseClient;
  try {
    const { getDatabaseClient } = require('./src/db/client');
    return getDatabaseClient(firebaseUid ? { firebaseUid } : {});
  } catch (_) {
    return null;
  }
}

/**
 * Storage authorization context (Postgres only). Accepts an injected PostgREST-compatible client
 * (`.from`) or `{ supabaseClient }`; otherwise routes by the caller's Firebase UID
 * (production demo accounts -> staging plane, real users -> RDS).
 */
async function resolveStorageContext(dbOrOptions, uid = null) {
  const injected = dbOrOptions && typeof dbOrOptions.from === 'function' ? dbOrOptions : null;
  const options = injected ? {} : (dbOrOptions || {});
  const supabase = injected || options.supabaseClient || getSupabaseAdminClient(uid);
  if (!supabase) {
    throw new HttpsError('unavailable', 'Database service temporarily unavailable.');
  }
  return { db: null, options, isSupabase: true, supabase };
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
    if (String(process.env.APP_ENV || '').trim().toLowerCase() === 'production') {
      return new S3Client({
        region: AWS_REGION,
        requestChecksumCalculation: 'WHEN_REQUIRED',
        responseChecksumValidation: 'WHEN_REQUIRED',
      });
    }
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
/**
 * Data-plane key prefixes (production only). One production bucket serves both planes, so
 * objects are namespaced: demo/ (reviewer / demo accounts on the staging Supabase plane) and
 * prod/ (real users on RDS). Keys created before prefixing (no prefix) belong to prod/.
 * Staging uses its own bucket and no prefix.
 */
const PLANE_PREFIXES = ['demo/', 'prod/'];

function isProductionStorage() {
  return String(process.env.APP_ENV || '').trim().toLowerCase() === 'production';
}

function planePrefixFor(uid) {
  if (!isProductionStorage()) return '';
  const { objectStoragePrefix } = require('./lib/demo_routing');
  return objectStoragePrefix({ appEnv: 'production', firebaseUid: uid || null });
}

function stripPlanePrefix(key) {
  const k = String(key || '');
  for (const p of PLANE_PREFIXES) if (k.startsWith(p)) return k.slice(p.length);
  return k;
}

/**
 * Maps a client-supplied physical key to its logical layout (health_records/..., lab_reports/...)
 * and rejects keys that belong to another data plane.
 */
function toLogicalKey(objectKey, uid) {
  const key = String(objectKey || '');
  if (!isProductionStorage()) return key;
  const explicit = PLANE_PREFIXES.find((p) => key.startsWith(p));
  const keyPlane = explicit || 'prod/';
  if (keyPlane !== planePrefixFor(uid)) {
    throw new HttpsError('permission-denied', 'You do not have permission to access this file.');
  }
  return explicit ? key.slice(explicit.length) : key;
}

function isPublicMediaKey(rawKey) {
  const key = stripPlanePrefix(rawKey);
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

const { resolveCallerIdentity } = require('./caller_identity');

/**
 * Resolves caller profile from users/{uid} or Supabase public.users.
 */
async function resolveCallerUser(db, uid, ctx = {}) {
  return resolveCallerIdentity({
    uid,
    supabaseClient: ctx.supabase || null,
  });
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
    case 'pharmacy_kyc':
    case 'pharmacyKyc':
      return 'pharmacy_kyc';
    case 'lab_kyc':
    case 'labKyc':
      return 'lab_kyc';
    case 'ambulance_kyc':
    case 'ambulanceKyc':
      return 'ambulance_kyc';
    default:
      return p;
  }
}

/**
 * Records an immutable access audit log row in public.storage_audit_logs.
 */
async function logStorageAccess(_db, { who, role, what, action, status = 'success', metadata = {} }, ctx = {}) {
  try {
    const supabase = ctx.supabase || null;
    if (!supabase) return;
    await supabase.from('storage_audit_logs').insert({
      who: String(who || '').trim(),
      role: String(role || '').trim(),
      what: String(what || '').trim(),
      action: String(action || '').trim(),
      status: String(status || '').trim(),
      created_at: new Date().toISOString(),
      metadata: metadata || {},
    });
  } catch (err) {
    console.error('[StorageAudit] Failed to record audit log:', err?.message || err);
  }
}

/**
 * 1. getS3UploadUrl core handler.
 */
async function getS3UploadUrlHandler(data, auth, dbOrOptions) {
  const ctx = await resolveStorageContext(dbOrOptions, auth?.uid);
  const { db, supabase } = ctx;

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

  const caller = await resolveCallerUser(db, auth.uid, ctx);
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

        const { data: booking } = await supabase
          .from('lab_bookings')
          .select('*')
          .eq('booking_id', bookingId)
          .maybeSingle();
        if (booking) {
          if (booking.status === 'cancelled') {
            throw new HttpsError('failed-precondition', 'Cannot upload report for a cancelled booking.');
          }
          if (booking.lab_id !== caller.profileId) {
            throw new HttpsError('permission-denied', 'This lab booking is not assigned to your laboratory.');
          }
          patientId = booking.patient_id;
        } else {
          const { data: order } = await supabase
            .from('lab_orders')
            .select('*')
            .eq('order_id', bookingId)
            .maybeSingle();
          if (order) {
            if (order.status === 'cancelled') {
              throw new HttpsError('failed-precondition', 'Cannot upload report for a cancelled lab order.');
            }
            if (order.lab_id !== caller.profileId) {
              throw new HttpsError('permission-denied', 'This lab order is not assigned to your laboratory.');
            }
            patientId = order.patient_id;
          } else {
            throw new HttpsError('not-found', 'Lab booking or order not found.');
          }
        }
      } else {
        const { data: booking } = await supabase
          .from('lab_bookings')
          .select('patient_id')
          .eq('booking_id', bookingId)
          .maybeSingle();
        patientId = booking?.patient_id || (parentId.includes('/') ? parentId.split('/')[0] : 'admin');
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
      if (!isAdmin && caller.role === 'patient') {
        throw new HttpsError('permission-denied', 'Patients are not permitted to create promotions.');
      }
      const adId = parentId;
      const providerId = auth.uid;
      objectKey = `promoted_ads/${providerId}/${adId}/${uuid}.jpg`;
      break;
    }

    case 'pharmacy_kyc': {
      const storeId = parentId;
      if (!isAdmin) {
        if (
          (caller.role !== 'medicalStore' && caller.role !== 'medical')
          || caller.profileId !== storeId
        ) {
          throw new HttpsError('permission-denied', 'Only the pharmacy owner can upload pharmacy KYC.');
        }
      }
      objectKey = `pharmacies/${storeId}/documents/${uuid}.${ext}`;
      break;
    }

    case 'lab_kyc': {
      const labId = parentId;
      if (!isAdmin) {
        if (caller.role !== 'lab' || caller.profileId !== labId) {
          throw new HttpsError('permission-denied', 'Only the lab owner can upload lab KYC.');
        }
      }
      objectKey = `labs/${labId}/documents/${uuid}.${ext}`;
      break;
    }

    case 'ambulance_kyc': {
      const ambulanceId = parentId;
      if (!isAdmin) {
        if (caller.role !== 'ambulance' || caller.profileId !== ambulanceId) {
          throw new HttpsError('permission-denied', 'Only the ambulance owner can upload ambulance KYC.');
        }
      }
      objectKey = `ambulances/${ambulanceId}/documents/${uuid}.${ext}`;
      break;
    }

    default:
      throw new HttpsError('invalid-argument', `Unknown storage purpose: '${purpose}'.`);
  }

  objectKey = planePrefixFor(auth?.uid) + objectKey;
  assertValidObjectKey(objectKey, 'objectKey');

  const s3 = getS3Client();
  const command = new PutObjectCommand({
    Bucket: s3Bucket(),
    Key: objectKey,
    ContentType: contentType,
    ContentLength: sizeBytes,
  });

  const uploadUrl = await getSignedUrl(s3, command, {
    expiresIn: 300,
    signableHeaders: new Set(['content-type', 'content-length', 'host']),
  });

  // Invalidate cached download URL on upload URL request to guard against serving stale content on overwrite
  await invalidateS3DownloadUrlCache(objectKey);

  // Record upload presigned audit log
  await logStorageAccess(db, {
    who: auth.uid,
    role: caller.role,
    what: objectKey,
    action: 'upload_presigned',
    status: 'success',
    metadata: {
      purpose,
      sizeBytes,
      contentType,
    },
  }, ctx);

  return {
    uploadUrl,
    objectKey,
  };
}

/**
 * Ensures lab_reports/{patientId}/{recordId}/… matches the booking/order row.
 */
async function labReportObjectKeyMatchesRecord(physicalKey, supabase) {
  const objectKey = stripPlanePrefix(physicalKey);
  const parts = objectKey.split('/');
  if (parts.length < 4 || parts[0] !== 'lab_reports') return false;
  const patientIdInKey = parts[1];
  const recordId = parts[2];
  const expectedPrefix = `lab_reports/${patientIdInKey}/${recordId}/`;
  if (!objectKey.startsWith(expectedPrefix)) return false;

  const { data: booking } = await supabase
    .from('lab_bookings')
    .select('patient_id, report_storage_key, report_s3_key')
    .eq('booking_id', recordId)
    .maybeSingle();
  if (booking) {
    if (booking.patient_id !== patientIdInKey) return false;
    const stored = booking.report_storage_key || booking.report_s3_key;
    if (stored && stored !== physicalKey && stored !== objectKey) return false;
    return true;
  }

  const { data: order } = await supabase
    .from('lab_orders')
    .select('patient_id, report_storage_key, report_s3_key')
    .eq('order_id', recordId)
    .maybeSingle();
  if (order) {
    if (order.patient_id !== patientIdInKey) return false;
    const stored = order.report_storage_key || order.report_s3_key;
    if (stored && stored !== physicalKey && stored !== objectKey) return false;
    return true;
  }

  return false;
}

/**
 * Authorizes read access to a given objectKey.
 */
async function authorizeRead(physicalKey, caller, auth, db, ctx = {}) {
  const objectKey = toLogicalKey(physicalKey, auth?.uid);
  if (isSuperAdmin(auth, caller)) return true;

  const parts = objectKey.split('/');
  const prefix = parts[0];
  const supabase = ctx.supabase || null;

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
      const { data: docData } = await supabase
        .from('doctors')
        .select('verified, deactivated')
        .eq('doctor_id', caller.profileId || '')
        .maybeSingle();
      if (!docData || docData.verified !== true || docData.deactivated === true) {
        return false;
      }

      // 2. Patient must allow record sharing
      const { data: pData } = await supabase
        .from('patients')
        .select('share_records_with_doctors')
        .eq('patient_id', patientId)
        .maybeSingle();
      if (!pData || pData.share_records_with_doctors === false) return false;

      // 3. Doctor must have clinical care relationship (link, appointment, or referral)
      const { data: linkRow } = await supabase
        .from('patient_doctor_links')
        .select('id')
        .eq('patient_id', patientId)
        .eq('doctor_id', caller.profileId)
        .maybeSingle();

      let hasRelationship = !!linkRow;
      if (!hasRelationship) {
        const { data: aptRow } = await supabase
          .from('appointments')
          .select('appointment_id')
          .eq('patient_id', patientId)
          .eq('doctor_id', caller.profileId)
          .limit(1)
          .maybeSingle();
        hasRelationship = !!aptRow;
      }
      if (!hasRelationship) {
        const { data: refRow } = await supabase
          .from('referrals')
          .select('referral_id')
          .eq('patient_id', patientId)
          .or(`from_doctor_id.eq.${caller.profileId},to_doctor_id.eq.${caller.profileId}`)
          .limit(1)
          .maybeSingle();
        hasRelationship = !!refRow;
      }
      if (!hasRelationship) return false;

      // 4. Record itself must have shared_with_doctors == true
      const { data: recordRow } = await supabase
        .from('health_records')
        .select('shared_with_doctors')
        .eq('record_id', recordId)
        .maybeSingle();
      if (recordRow && recordRow.shared_with_doctors === false) {
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
      return labReportObjectKeyMatchesRecord(physicalKey, supabase);
    }

    if (caller.role === 'lab') {
      const { data: booking } = await supabase
        .from('lab_bookings')
        .select('lab_id, status')
        .eq('booking_id', bookingId)
        .maybeSingle();
      if (booking && booking.lab_id === caller.profileId && booking.status !== 'cancelled') {
        return labReportObjectKeyMatchesRecord(physicalKey, supabase);
      }
      const { data: order } = await supabase
        .from('lab_orders')
        .select('lab_id, status')
        .eq('order_id', bookingId)
        .maybeSingle();
      if (order && order.lab_id === caller.profileId && order.status !== 'cancelled') {
        return labReportObjectKeyMatchesRecord(physicalKey, supabase);
      }
      return false;
    }

    return false;
  }

  if (prefix === 'prescriptions') {
    // prescriptions/{patientId}/{prescriptionId}/{fileName}
    const patientId = parts[1];
    const prescriptionId = parts[2];

    if (caller.role === 'patient' && caller.profileId === patientId) {
      return true;
    }

    if (caller.role === 'doctor') {
      const { data: rx } = await supabase
        .from('prescriptions')
        .select('doctor_id')
        .eq('prescription_id', prescriptionId)
        .maybeSingle();
      if (rx && rx.doctor_id === caller.profileId) {
        return true;
      }
    }

    if (caller.role === 'medicalStore' || caller.role === 'medical') {
      const { data: deliv } = await supabase
        .from('pharmacy_deliveries')
        .select('delivery_id')
        .eq('prescription_id', prescriptionId)
        .eq('store_id', caller.profileId)
        .limit(1)
        .maybeSingle();
      if (deliv) return true;
    }

    return false;
  }

  return false;
}

/**
 * Authorizes delete access to a given objectKey (owner-only or super admin).
 */
async function authorizeDelete(physicalKey, caller, auth, db, ctx = {}) {
  const objectKey = toLogicalKey(physicalKey, auth?.uid);
  if (isSuperAdmin(auth, caller)) return true;

  const parts = objectKey.split('/');
  const prefix = parts[0];
  const supabase = ctx.supabase || null;

  if (prefix === 'health_records') {
    // health_records/{patientId}/{recordId}/{fileName}
    const patientId = parts[1];
    return caller.role === 'patient' && caller.profileId === patientId;
  }

  if (prefix === 'lab_reports') {
    // lab_reports/{patientId}/{bookingId}/{fileName}
    const bookingId = parts[2];
    if (caller.role === 'lab') {
      const { data: booking } = await supabase
        .from('lab_bookings')
        .select('lab_id')
        .eq('booking_id', bookingId)
        .maybeSingle();
      if (booking && booking.lab_id === caller.profileId) {
        return true;
      }
      const { data: order } = await supabase
        .from('lab_orders')
        .select('lab_id')
        .eq('order_id', bookingId)
        .maybeSingle();
      if (order && order.lab_id === caller.profileId) {
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

  if (prefix === 'pharmacies') {
    return (caller.role === 'medicalStore' || caller.role === 'medical')
      && caller.profileId === parts[1];
  }

  if (prefix === 'labs') {
    return caller.role === 'lab' && caller.profileId === parts[1];
  }

  if (prefix === 'ambulances') {
    return caller.role === 'ambulance' && caller.profileId === parts[1];
  }

  return false;
}

function hashKey(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

const S3_URL_CACHE_BUFFER_SEC = 900;

function s3DownloadUrlCacheKeyPrefix(objectKey) {
  return envRedisKey(`s3:dl:${hashKey(String(objectKey || ''))}:`);
}

function s3DownloadUrlCacheKey(objectKey, principalId) {
  const principal = hashKey(String(principalId || ''));
  return `${s3DownloadUrlCacheKeyPrefix(objectKey)}${principal}`;
}

function getS3UrlCacheConfig() {
  return String(process.env.S3_URL_CACHE || 'off').trim().toLowerCase();
}

function withRedisTimeout(promise, ms = 1500) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('Redis S3 URL cache operation timed out')), ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => clearTimeout(timer));
}

async function redisDeleteKeysByPrefix(redis, prefix) {
  if (!redis || !prefix) return;
  const match = `${prefix}*`;
  if (typeof redis.scan === 'function') {
    let cursor = '0';
    const keys = [];
    do {
      const res = await redis.scan(cursor, 'MATCH', match, 'COUNT', 64);
      cursor = res[0];
      if (Array.isArray(res[1]) && res[1].length) keys.push(...res[1]);
    } while (cursor !== '0');
    if (keys.length && typeof redis.del === 'function') {
      await redis.del(...keys);
    }
    return;
  }
  if (typeof redis.del === 'function') {
    await redis.del(prefix);
  }
}

async function getCachedDownloadUrl(objectKey, principalId) {
  if (getS3UrlCacheConfig() !== 'on' || !objectKey || !principalId) return null;
  try {
    const { redis } = require('./redis');
    if (!redis) return null;
    const key = s3DownloadUrlCacheKey(objectKey, principalId);
    const raw = await withRedisTimeout(redis.get(key), 1500).catch(() => null);
    if (!raw) return null;
    const ttl = await withRedisTimeout(redis.ttl(key), 1500).catch(() => 0);
    if (ttl <= 0 || ttl < S3_URL_CACHE_BUFFER_SEC) return null;
    return {
      url: String(raw),
      remainingTtlSec: ttl + S3_URL_CACHE_BUFFER_SEC,
    };
  } catch (_) {
    return null;
  }
}

async function setCachedDownloadUrl(objectKey, url, ttlSec, principalId) {
  if (getS3UrlCacheConfig() !== 'on' || !objectKey || !url || !principalId) return;
  const ttl = Number(ttlSec);
  if (!Number.isFinite(ttl) || ttl <= 0) return;
  try {
    const { redis } = require('./redis');
    if (!redis) return;
    const key = s3DownloadUrlCacheKey(objectKey, principalId);
    await withRedisTimeout(redis.set(key, url, 'EX', ttl), 1500).catch(() => {});
  } catch (_) {}
}

async function invalidateS3DownloadUrlCache(objectKey) {
  if (getS3UrlCacheConfig() !== 'on' || !objectKey) return;
  try {
    const { redis } = require('./redis');
    if (!redis) return;
    await withRedisTimeout(
      redisDeleteKeysByPrefix(redis, s3DownloadUrlCacheKeyPrefix(objectKey)),
      3000,
    ).catch(() => {});
  } catch (_) {}
}

async function invalidateS3DownloadUrlCacheBatch(objectKeys) {
  if (getS3UrlCacheConfig() !== 'on' || !Array.isArray(objectKeys) || objectKeys.length === 0) return;
  try {
    const { redis } = require('./redis');
    if (!redis) return;
    for (const objectKey of objectKeys.filter(Boolean)) {
      await withRedisTimeout(
        redisDeleteKeysByPrefix(redis, s3DownloadUrlCacheKeyPrefix(objectKey)),
        3000,
      ).catch(() => {});
    }
  } catch (_) {}
}

/**
 * 2. getS3DownloadUrl core handler.
 */
async function getS3DownloadUrlHandler(data, auth, dbOrOptions) {
  const ctx = await resolveStorageContext(dbOrOptions, auth?.uid);
  const objectKey = String(data?.objectKey || '').trim();
  if (!objectKey) {
    throw new HttpsError('invalid-argument', 'objectKey is required.');
  }
  assertValidObjectKey(objectKey, 'objectKey');

  // ORDER MATTERS: run authorization check on EVERY request first.
  const caller = await resolveCallerUser(ctx.db, auth.uid, ctx);
  const allowed = await authorizeRead(objectKey, caller, auth, ctx.db, ctx);
  if (!allowed) {
    throw new HttpsError('permission-denied', 'You do not have permission to access this file.');
  }

  // PHI / KYC objects: always a fresh 5-minute URL, never cached (cache is for public media only).
  const isSensitiveObject = !isPublicMediaKey(objectKey);

  // Only after authorization passes, check the download URL cache
  if (!isSensitiveObject && getS3UrlCacheConfig() === 'on') {
    const cached = await getCachedDownloadUrl(objectKey, auth.uid);
    if (cached) {
      return {
        url: cached.url,
        expiresIn: cached.remainingTtlSec,
        cached: true,
      };
    }
  }

  const s3 = getS3Client();
  const command = new GetObjectCommand({
    Bucket: s3Bucket(),
    Key: objectKey,
  });

  const isCacheOn = !isSensitiveObject && getS3UrlCacheConfig() === 'on';
  const expiresIn = isCacheOn ? 3600 : 300;
  const url = await getSignedUrl(s3, command, { expiresIn });

  if (isCacheOn) {
    // Cache for (expiresIn - 900) seconds = 2700s (45 minutes)
    const cacheTtlSec = Math.max(1, expiresIn - 900);
    await setCachedDownloadUrl(objectKey, url, cacheTtlSec, auth.uid);
  }

  // Record download audit log
  await logStorageAccess(ctx.db, {
    who: auth.uid,
    role: caller.role,
    what: objectKey,
    action: 'download_presigned',
    status: 'success',
  }, ctx);

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
async function getS3DownloadUrlsHandler(data, auth, dbOrOptions) {
  const ctx = await resolveStorageContext(dbOrOptions, auth?.uid);
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

  const caller = await resolveCallerUser(ctx.db, auth.uid, ctx);
  const s3 = getS3Client();
  const urls = {};
  const isCacheOn = getS3UrlCacheConfig() === 'on';
  const expiresIn = 3600; // 1 hour for batch media

  for (const rawKey of objectKeys) {
    const key = String(rawKey || '').trim();

    // ORDER MATTERS: authorize each key first
    const allowed = await authorizeRead(key, caller, auth, ctx.db, ctx);
    if (!allowed) continue;

    if (isCacheOn) {
      const cached = await getCachedDownloadUrl(key, auth.uid);
      if (cached) {
        urls[key] = cached.url;
        continue;
      }
    }

    const command = new GetObjectCommand({
      Bucket: s3Bucket(),
      Key: key,
    });
    try {
      const signedUrl = await getSignedUrl(s3, command, { expiresIn });
      urls[key] = signedUrl;
      if (isCacheOn) {
        const cacheTtlSec = Math.max(1, expiresIn - 900);
        await setCachedDownloadUrl(key, signedUrl, cacheTtlSec, auth.uid);
      }
    } catch (_) {
      // Omit failed keys from response map
    }
  }

  // Record batch download audit log
  await logStorageAccess(ctx.db, {
    who: auth.uid,
    role: caller.role,
    what: `${Object.keys(urls).length}/${objectKeys.length} keys`,
    action: 'batch_download_presigned',
    status: 'success',
    metadata: {
      requestedCount: objectKeys.length,
      resolvedCount: Object.keys(urls).length,
    },
  }, ctx);

  return { urls };
}

/**
 * 4. deleteS3Object core handler.
 */
async function deleteS3ObjectHandler(data, auth, dbOrOptions) {
  const ctx = await resolveStorageContext(dbOrOptions, auth?.uid);
  const objectKey = String(data?.objectKey || '').trim();
  if (!objectKey) {
    throw new HttpsError('invalid-argument', 'objectKey is required.');
  }
  assertValidObjectKey(objectKey, 'objectKey');

  const caller = await resolveCallerUser(ctx.db, auth.uid, ctx);
  const allowed = await authorizeDelete(objectKey, caller, auth, ctx.db, ctx);
  if (!allowed) {
    throw new HttpsError('permission-denied', 'You do not have permission to delete this file.');
  }

  const s3 = getS3Client();
  await s3.send(
    new DeleteObjectCommand({
      Bucket: s3Bucket(),
      Key: objectKey,
    }),
  );

  // Invalidate cached download URL on object delete
  await invalidateS3DownloadUrlCache(objectKey);

  // Record delete audit log
  await logStorageAccess(ctx.db, {
    who: auth.uid,
    role: caller.role,
    what: objectKey,
    action: 'delete',
    status: 'success',
  }, ctx);

  return {
    success: true,
    objectKey,
  };
}

const FILE_SIGNATURES = Object.freeze({
  'image/jpeg': (b) => b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  'image/png': (b) => b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47
    && b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a,
  'image/webp': (b) => b.length >= 12 && b.slice(0, 4).toString('latin1') === 'RIFF'
    && b.slice(8, 12).toString('latin1') === 'WEBP',
  'application/pdf': (b) => b.length >= 5 && b.slice(0, 5).toString('latin1') === '%PDF-',
});

/**
 * Reads the first 16 bytes of an object and checks them against the declared content type.
 * @returns {Promise<boolean|null>} true/false when verified; null when the client returned no body.
 */
async function sniffObjectSignature(s3, objectKey, contentType) {
  const check = FILE_SIGNATURES[contentType];
  if (!check) return false;
  let res;
  try {
    res = await s3.send(new GetObjectCommand({ Bucket: s3Bucket(), Key: objectKey, Range: 'bytes=0-15' }));
  } catch (_) {
    return false;
  }
  const body = res && res.Body;
  if (!body) return null;
  let bytes;
  try {
    if (typeof body.transformToByteArray === 'function') {
      bytes = Buffer.from(await body.transformToByteArray());
    } else if (Buffer.isBuffer(body) || body instanceof Uint8Array) {
      bytes = Buffer.from(body);
    } else {
      return null;
    }
  } catch (_) {
    return false;
  }
  return check(bytes);
}

/** purpose -> object key prefix produced by getS3UploadUrlHandler. */
const CONFIRM_PURPOSE_PREFIX = Object.freeze({
  health_records: 'health_records',
  lab_reports: 'lab_reports',
  patient_profile: 'patients',
  doctor_profile: 'doctor_profiles',
  promoted_ads: 'promoted_ads',
  pharmacy_kyc: 'pharmacies',
  lab_kyc: 'labs',
  ambulance_kyc: 'ambulances',
});

/**
 * 5. confirmS3Upload core handler.
 * Verifies object existence, Content-Length, and Content-Type via S3 HEAD before linking s3_key in DB.
 * On failed validation (size/type/missing), deletes the uploaded object and records an audit log.
 *
 * Idempotency: safe to call repeatedly with the same objectKey/recordId/purpose — HEAD is re-run and
 * DB update sets the same columns (Supabase .update / Firestore merge). No row delete or key rotation.
 * Client orphan cleanup: if PUT succeeds but confirm fails after retries, Flutter deletes via presign
 * deleteObject; otherwise configure S3 lifecycle on unconfirmed prefixes (see docs/audit/S3_CONFIRM_ORPHANS.md).
 */
async function confirmS3UploadHandler(data, auth, dbOrOptions) {
  const ctx = await resolveStorageContext(dbOrOptions, auth?.uid);
  const objectKey = String(data?.objectKey || '').trim();
  const recordId = String(data?.recordId || '').trim();
  const purpose = normalizePurpose(data?.purpose);

  if (!objectKey) {
    throw new HttpsError('invalid-argument', 'objectKey is required.');
  }
  assertValidObjectKey(objectKey, 'objectKey');

  if (!purpose) {
    throw new HttpsError('invalid-argument', 'purpose is required.');
  }

  const caller = await resolveCallerUser(ctx.db, auth.uid, ctx);

  // Authorize upload confirmation BEFORE any S3 call (this handler can delete objects).
  // 1) purpose must match the key prefix (blocks image-size limits being applied to
  //    someone else's documents to trigger deletion);
  // 2) caller must own the key exactly as for delete (lab must own the booking, etc.).
  //    Unknown prefixes (e.g. prescriptions/) are denied by default.
  const parts = toLogicalKey(objectKey, auth?.uid).split('/');
  const prefix = parts[0];
  const expectedPrefix = CONFIRM_PURPOSE_PREFIX[purpose];
  if (!expectedPrefix || expectedPrefix !== prefix) {
    throw new HttpsError('permission-denied', 'You do not have permission to confirm this upload.');
  }
  const confirmAllowed = await authorizeDelete(objectKey, caller, auth, ctx.db, ctx);
  if (!confirmAllowed) {
    throw new HttpsError('permission-denied', 'You do not have permission to confirm this upload.');
  }

  // Verify object in S3 via HeadObjectCommand
  const s3 = getS3Client();
  let head;
  try {
    head = await s3.send(
      new HeadObjectCommand({
        Bucket: s3Bucket(),
        Key: objectKey,
      }),
    );
  } catch (err) {
    await s3.send(new DeleteObjectCommand({ Bucket: s3Bucket(), Key: objectKey })).catch(() => {});
    await logStorageAccess(ctx.db, {
      who: auth.uid,
      role: caller.role,
      what: objectKey,
      action: 'upload_confirm_failed',
      status: 'head_not_found',
      metadata: { error: err.message },
    }, ctx);
    throw new HttpsError('not-found', 'Uploaded file was not found in S3 or is inaccessible.');
  }

  const contentType = String(head.ContentType || '').toLowerCase();
  const contentLength = Number(head.ContentLength || 0);

  // Enforce content-type allowlist
  if (!ALLOWED_CONTENT_TYPES.has(contentType)) {
    await s3.send(new DeleteObjectCommand({ Bucket: s3Bucket(), Key: objectKey })).catch(() => {});
    await logStorageAccess(ctx.db, {
      who: auth.uid,
      role: caller.role,
      what: objectKey,
      action: 'upload_confirm_failed',
      status: 'invalid_content_type',
      metadata: { contentType },
    }, ctx);
    throw new HttpsError('failed-precondition', `Invalid S3 object Content-Type: ${contentType}`);
  }

  // Enforce max size limits
  const isImagePurpose =
    purpose === 'patient_profile' ||
    purpose === 'doctor_profile' ||
    purpose === 'promoted_ads';

  const maxAllowedBytes = isImagePurpose ? MAX_IMAGE_BYTES : MAX_DOC_BYTES;
  if (contentLength <= 0 || contentLength > maxAllowedBytes) {
    await s3.send(new DeleteObjectCommand({ Bucket: s3Bucket(), Key: objectKey })).catch(() => {});
    await logStorageAccess(ctx.db, {
      who: auth.uid,
      role: caller.role,
      what: objectKey,
      action: 'upload_confirm_failed',
      status: 'size_exceeded',
      metadata: { contentLength, maxAllowedBytes },
    }, ctx);
    throw new HttpsError('failed-precondition', `S3 object size ${contentLength} bytes exceeds limit of ${maxAllowedBytes} bytes.`);
  }

  // Content-Type is client-declared at PUT time: verify the real file signature (magic bytes).
  const sniff = await sniffObjectSignature(s3, objectKey, contentType);
  if (sniff === false) {
    await s3.send(new DeleteObjectCommand({ Bucket: s3Bucket(), Key: objectKey })).catch(() => {});
    await logStorageAccess(ctx.db, {
      who: auth.uid,
      role: caller.role,
      what: objectKey,
      action: 'upload_confirm_failed',
      status: 'magic_bytes_mismatch',
      metadata: { contentType },
    }, ctx);
    throw new HttpsError('failed-precondition', 'Uploaded file content does not match its declared type.');
  }

  // Update DB row if recordId is provided. The row is bound to the AUTHORIZED key, never to the
  // client-supplied recordId alone: health_records/{patientId}/{recordId}/..., lab_reports/{patientId}/{bookingId}/...
  // (previously any recordId was accepted, letting a caller re-point another patient's record at its file).
  const keyParts = toLogicalKey(objectKey, auth?.uid).split('/');
  if (recordId && (purpose === 'health_records' || purpose === 'lab_reports') && keyParts[2] !== recordId) {
    throw new HttpsError('permission-denied', 'recordId does not match the uploaded object.');
  }
  if (recordId) {
    if (purpose === 'health_records') {
      await ctx.supabase
        .from('health_records')
        .update({
          s3_key: objectKey,
          s3_bucket: s3Bucket(),
          storage_key: objectKey,
          storage_provider: 's3',
          file_size_bytes: contentLength,
          mime_type: contentType,
          upload_confirmed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('record_id', recordId)
        .eq('patient_id', keyParts[1]);
    } else if (purpose === 'lab_reports') {
      await ctx.supabase
        .from('lab_bookings')
        .update({
          report_s3_key: objectKey,
          report_s3_bucket: s3Bucket(),
          report_storage_key: objectKey,
          report_storage_provider: 's3',
          report_file_size_bytes: contentLength,
          report_mime_type: contentType,
          report_uploaded_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('booking_id', recordId)
        .eq('patient_id', keyParts[1]);
    } else if (purpose === 'patient_profile') {
      const targetId = caller.profileId || recordId;
      await ctx.supabase
        .from('patients')
        .update({
          photo_s3_key: objectKey,
          photo_s3_bucket: s3Bucket(),
          photo_storage_provider: 's3',
          photo_updated_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('patient_id', targetId);
    } else if (purpose === 'doctor_profile') {
      const targetId = caller.profileId || recordId;
      await ctx.supabase
        .from('doctors')
        .update({
          photo_s3_key: objectKey,
          photo_s3_bucket: s3Bucket(),
          photo_storage_provider: 's3',
          photo_updated_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('doctor_id', targetId);
    }
  }

  // Record audit log
  await logStorageAccess(ctx.db, {
    who: auth.uid,
    role: caller.role,
    what: objectKey,
    action: 'upload_confirmed',
    status: 'success',
    metadata: {
      contentLength,
      contentType,
      recordId,
      purpose,
    },
  }, ctx);

  return {
    success: true,
    objectKey,
    contentLength,
    contentType,
  };
}

// ----------------------------------------------------------------------------
// EXPORTED CLOUD FUNCTIONS (Callable v2, asia-south1, with secrets & abuse guard)
// ----------------------------------------------------------------------------

const CALLABLE_OPTIONS = {
  region: CALLABLE_REGION,
  secrets: [awsAccessKeyId, awsSecretAccessKey, supabaseServiceRoleKey],
  enforceAppCheck: ENFORCE_ABUSE_APP_CHECK,
};

exports.getS3UploadUrl = onCall(CALLABLE_OPTIONS, async (request) => {
  requireAuth(request);
  await enforceAbuseLimit(null, request, 'api');
  return getS3UploadUrlHandler(request.data, request.auth, null);
});

exports.getS3DownloadUrl = onCall(CALLABLE_OPTIONS, async (request) => {
  requireAuth(request);
  await enforceAbuseLimit(null, request, 'api');
  return getS3DownloadUrlHandler(request.data, request.auth, null);
});

exports.getS3DownloadUrls = onCall(CALLABLE_OPTIONS, async (request) => {
  requireAuth(request);
  await enforceAbuseLimit(null, request, 'api');
  return getS3DownloadUrlsHandler(request.data, request.auth, null);
});

exports.deleteS3Object = onCall(CALLABLE_OPTIONS, async (request) => {
  requireAuth(request);
  await enforceAbuseLimit(null, request, 'api');
  return deleteS3ObjectHandler(request.data, request.auth, null);
});

exports.confirmS3Upload = onCall(CALLABLE_OPTIONS, async (request) => {
  requireAuth(request);
  await enforceAbuseLimit(null, request, 'api');
  return confirmS3UploadHandler(request.data, request.auth, null);
});

exports.awsAccessKeyId = awsAccessKeyId;
exports.awsSecretAccessKey = awsSecretAccessKey;
exports.supabaseServiceRoleKey = supabaseServiceRoleKey;

exports.s3DownloadUrlCacheKey = s3DownloadUrlCacheKey;
exports.s3DownloadUrlCacheKeyPrefix = s3DownloadUrlCacheKeyPrefix;
exports.getCachedDownloadUrl = getCachedDownloadUrl;
exports.setCachedDownloadUrl = setCachedDownloadUrl;
exports.invalidateS3DownloadUrlCache = invalidateS3DownloadUrlCache;
exports.invalidateS3DownloadUrlCacheBatch = invalidateS3DownloadUrlCacheBatch;
exports.getS3UrlCacheConfig = getS3UrlCacheConfig;

// Export handlers & testing helpers for unit tests
exports._test = {
  getS3UploadUrlHandler,
  getS3DownloadUrlHandler,
  getS3DownloadUrlsHandler,
  deleteS3ObjectHandler,
  confirmS3UploadHandler,
  logStorageAccess,
  setS3ClientForTesting,
  setSupabaseClientForTesting,
  validateContentTypeAndSize,
  toLogicalKey,
  planePrefixFor,
  stripPlanePrefix,
  extractExtension,
  authorizeRead,
  authorizeDelete,
  isSuperAdmin,
  isValidObjectKey,
  assertValidObjectKey,
  isPublicMediaKey,
  s3DownloadUrlCacheKey,
  getCachedDownloadUrl,
  setCachedDownloadUrl,
  invalidateS3DownloadUrlCache,
  invalidateS3DownloadUrlCacheBatch,
  getS3UrlCacheConfig,
};

