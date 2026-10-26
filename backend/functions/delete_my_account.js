const { resolveCallerIdentity } = require('./caller_identity');
'use strict';
require('./firestore_forbidden_guard');

const crypto = require('crypto');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const { logger } = require('firebase-functions');
const { HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { toUserUuid } = require('./user_id_bridge');
const { readSupabaseServiceRoleKey } = require('./secure_config');


const supabaseServiceRoleKey = defineSecret('SUPABASE_SERVICE_ROLE_KEY');

let _testingSupabaseFetch = null;
function setSupabaseFetchForTesting(fn) {
  _testingSupabaseFetch = fn;
}
let _s3Sdk;
function getS3Sdk() {
  if (!_s3Sdk) {
    _s3Sdk = require('@aws-sdk/client-s3');
  }
  return _s3Sdk;
}

const S3_BUCKET = process.env.S3_BUCKET || 'doctornect';
let _testingS3Client = null;

function setS3ClientForTesting(client) {
  _testingS3Client = client;
}

function getS3Client() {
  if (_testingS3Client) return _testingS3Client;
  const { S3Client } = getS3Sdk();
  const region = process.env.AWS_REGION || 'ap-south-1';
  return new S3Client({
    region,
    credentials:
      process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY
        ? {
            accessKeyId: process.env.AWS_ACCESS_KEY_ID,
            secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
          }
        : undefined,
  });
}

/**
 * Deletes OTP challenge keys from Redis for the deleting user.
 * Best-effort, fail-soft.
 */
async function cleanupUserRedisKeys({ mobileDigits, role }) {
  if (String(process.env.OTP_REDIS_MIRROR || '').trim().toLowerCase() !== 'on') {
    return;
  }
  const digits = normalizeMobileDigits(mobileDigits);
  if (!digits) return;
  try {
    const { getRedisClient } = require('./redis');
    const redis = getRedisClient();
    if (!redis) return;
    const roles = ['patient', 'doctor', 'medicalStore', 'lab', 'ambulance', null];
    if (role && !roles.includes(role)) roles.push(role);
    const keys = roles.map((r) => (r ? `otp:challenge:${r}:${digits}` : `otp:challenge:${digits}`));
    await Promise.all(keys.map((k) => (typeof redis.del === 'function' ? redis.del(k) : Promise.resolve()).catch(() => {})));
  } catch (err) {
    logger.warn('deleteMyAccount: Redis cleanup failed (soft-fail)', {
      error: err?.message || 'unknown',
    });
  }
}

const OTP_ROLES = ['patient', 'doctor', 'medicalStore', 'medical', 'lab', 'ambulance'];
const ABUSE_CATEGORIES = ['api', 'login', 'signup', 'ai', 'scrape', 'payment'];

function hashKey(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

function mobileHash(role, digits) {
  const normRole = (role === 'medical' || role === 'pharmacy') ? 'medicalStore' : role;
  return crypto.createHash('sha256').update(`${normRole}:${digits}`).digest('hex');
}

function normalizeMobileDigits(mobile) {
  const digits = String(mobile || '').replace(/\D/g, '');
  let normalized = digits;
  if (normalized.length === 12 && normalized.startsWith('91')) {
    normalized = normalized.slice(2);
  } else if (normalized.length === 11 && normalized.startsWith('0')) {
    normalized = normalized.slice(1);
  }
  if (normalized.length !== 10 || !/^[6-9]\d{9}$/.test(normalized)) return '';
  return normalized;
}

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

async function deleteDocIfExists(db, ref) {
  const snap = await ref.get();
  if (!snap.exists) return;
  await db.recursiveDelete(ref);
}

async function deleteWhere(db, collection, field, value) {
  const normalized = String(value || '').trim();
  if (!normalized) return;

  let lastDoc = null;
  while (true) {
    let query = db.collection(collection).where(field, '==', normalized).limit(200);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      await db.recursiveDelete(doc.ref);
    }

    if (snap.size < 200) break;
    lastDoc = snap.docs[snap.docs.length - 1];
  }
}

async function deleteStoragePrefix(bucket, prefix) {
  const normalized = String(prefix || '').trim();
  if (!normalized) return;
  try {
    await bucket.deleteFiles({ prefix: normalized });
  } catch (err) {
    logger.warn('deleteMyAccount storage prefix delete failed', {
      prefix: normalized,
      code: err?.code || 'unknown',
    });
  }
}

/**
 * Deletes all objects, versions, and delete markers under an S3 prefix in batches of up to 1000.
 * Best-effort: catches errors, logs warnings, and returns success status.
 */
async function deleteS3PrefixVersions(s3, bucketName, prefix) {
  const normalizedPrefix = String(prefix || '').trim();
  if (!normalizedPrefix) return { success: true, count: 0, prefix: '' };

  let totalDeleted = 0;
  let keyMarker = undefined;
  let versionIdMarker = undefined;

  const { ListObjectVersionsCommand, DeleteObjectsCommand } = getS3Sdk();
  try {
    while (true) {
      const listCmd = new ListObjectVersionsCommand({
        Bucket: bucketName,
        Prefix: normalizedPrefix,
        KeyMarker: keyMarker,
        VersionIdMarker: versionIdMarker,
      });

      const res = await s3.send(listCmd);
      const items = [];

      if (res.Versions && Array.isArray(res.Versions)) {
        for (const v of res.Versions) {
          if (v.Key) {
            items.push({ Key: v.Key, VersionId: v.VersionId });
          }
        }
      }

      if (res.DeleteMarkers && Array.isArray(res.DeleteMarkers)) {
        for (const dm of res.DeleteMarkers) {
          if (dm.Key) {
            items.push({ Key: dm.Key, VersionId: dm.VersionId });
          }
        }
      }

      for (let i = 0; i < items.length; i += 1000) {
        const batch = items.slice(i, i + 1000);
        if (batch.length > 0) {
          const deleteCmd = new DeleteObjectsCommand({
            Bucket: bucketName,
            Delete: {
              Objects: batch,
              Quiet: true,
            },
          });
          await s3.send(deleteCmd);
          totalDeleted += batch.length;
          try {
            const { invalidateS3DownloadUrlCacheBatch } = require('./s3_storage');
            await invalidateS3DownloadUrlCacheBatch(batch.map((b) => b.Key));
          } catch (_) {}
        }
      }

      if (!res.IsTruncated) {
        break;
      }
      keyMarker = res.NextKeyMarker;
      versionIdMarker = res.NextVersionIdMarker;
    }

    return { success: true, count: totalDeleted, prefix: normalizedPrefix };
  } catch (err) {
    logger.warn('deleteMyAccount S3 prefix delete failed', {
      prefix: normalizedPrefix,
      message: err?.message || 'unknown',
    });
    return { success: false, error: err?.message || 'unknown', prefix: normalizedPrefix };
  }
}

/**
 * Deletes all versions and delete markers for a specific list of exact S3 keys.
 * Best-effort: catches errors per key/batch, logs warnings, and batches deletes up to 1000 items.
 */
async function deleteS3SpecificKeysVersions(s3, bucketName, keys) {
  const normalizedKeys = Array.from(
    new Set((keys || []).map((k) => String(k || '').trim()).filter(Boolean)),
  );
  if (normalizedKeys.length === 0) return { success: true, count: 0, failedKeys: [] };

  const itemsToDelete = [];
  const failedKeys = [];

  const { ListObjectVersionsCommand, DeleteObjectsCommand } = getS3Sdk();
  for (const key of normalizedKeys) {
    try {
      let keyMarker = undefined;
      let versionIdMarker = undefined;
      let keyFound = false;

      while (true) {
        const listCmd = new ListObjectVersionsCommand({
          Bucket: bucketName,
          Prefix: key,
          KeyMarker: keyMarker,
          VersionIdMarker: versionIdMarker,
        });

        const res = await s3.send(listCmd);

        if (res.Versions && Array.isArray(res.Versions)) {
          for (const v of res.Versions) {
            // Strictly match the exact key to prevent prefix collisions
            if (v.Key === key) {
              keyFound = true;
              itemsToDelete.push({ Key: v.Key, VersionId: v.VersionId });
            }
          }
        }

        if (res.DeleteMarkers && Array.isArray(res.DeleteMarkers)) {
          for (const dm of res.DeleteMarkers) {
            if (dm.Key === key) {
              keyFound = true;
              itemsToDelete.push({ Key: dm.Key, VersionId: dm.VersionId });
            }
          }
        }

        if (!res.IsTruncated) {
          break;
        }
        keyMarker = res.NextKeyMarker;
        versionIdMarker = res.NextVersionIdMarker;
      }

      // If ListObjectVersions didn't return version entries (e.g. unversioned), still target key
      if (!keyFound) {
        itemsToDelete.push({ Key: key });
      }
    } catch (err) {
      logger.warn('deleteS3SpecificKeysVersions list error', {
        key,
        message: err?.message || 'unknown',
      });
      failedKeys.push(key);
    }
  }

  let totalDeleted = 0;
  for (let i = 0; i < itemsToDelete.length; i += 1000) {
    const batch = itemsToDelete.slice(i, i + 1000);
    if (batch.length > 0) {
      try {
        const deleteCmd = new DeleteObjectsCommand({
          Bucket: bucketName,
          Delete: {
            Objects: batch,
            Quiet: true,
          },
        });
        await s3.send(deleteCmd);
        totalDeleted += batch.length;
        try {
          const { invalidateS3DownloadUrlCacheBatch } = require('./s3_storage');
          await invalidateS3DownloadUrlCacheBatch(batch.map((item) => item.Key));
        } catch (_) {}
      } catch (err) {
        logger.warn('deleteS3SpecificKeysVersions delete batch error', {
          batchSize: batch.length,
          message: err?.message || 'unknown',
        });
        for (const item of batch) {
          failedKeys.push(item.Key);
        }
      }
    }
  }

  return {
    success: failedKeys.length === 0,
    count: totalDeleted,
    failedKeys: Array.from(new Set(failedKeys)),
  };
}

async function getOwnedProfileIds(db, collection, field, uid) {
  const normalizedUid = String(uid || '').trim();
  if (!normalizedUid) return [];
  const snap = await db.collection(collection).where(field, '==', normalizedUid).get();
  return snap.docs.map((doc) => doc.id);
}

/**
 * Resolves all S3 prefixes that belong to a user/profile.
 * - patients/{patientId}/
 * - doctor_profiles/{doctorId}/
 * - health_records/{patientId}/
 * - lab_reports/{patientId}/ (only if the user is the patient; NOT deleted for lab accounts)
 * - promoted_ads/{providerId}/ (if provider)
 */
async function resolveUserS3Prefixes(db, { uid, role, profileId }) {
  const prefixes = new Set();

  // 1. Promoted ad banners for provider or user
  const isProvider = ['doctor', 'lab', 'pharmacy', 'medicalStore', 'medical', 'ambulance'].includes(role);
  if (isProvider || uid) {
    prefixes.add(`promoted_ads/${uid}/`);
    if (profileId && profileId !== uid) {
      prefixes.add(`promoted_ads/${profileId}/`);
    }
  }

  // 2. Patient profiles (own profileId + any owned patient docs)
  if (role === 'patient') {
    let ownedPatientIds = [];
    try {
      ownedPatientIds = await getOwnedProfileIds(db, 'patients', 'ownerUid', uid);
    } catch (_) {}
    const patientIds = new Set([profileId, uid, ...ownedPatientIds].filter(Boolean));
    for (const pid of patientIds) {
      prefixes.add(`patients/${pid}/`);
      prefixes.add(`health_records/${pid}/`);
      prefixes.add(`lab_reports/${pid}/`); // User IS the patient: clean up their reports
    }
  }

  // 3. Doctor profiles (own profileId + any owned doctor docs)
  if (role === 'doctor') {
    let ownedDoctorIds = [];
    try {
      ownedDoctorIds = await getOwnedProfileIds(db, 'doctors', 'ownerUid', uid);
    } catch (_) {}
    const doctorIds = new Set([profileId, uid, ...ownedDoctorIds].filter(Boolean));
    for (const did of doctorIds) {
      prefixes.add(`doctor_profiles/${did}/`);
    }
  }

  // 4. Lab profiles (own profileId + any owned lab docs)
  if (role === 'lab') {
    let ownedLabIds = [];
    try {
      ownedLabIds = await getOwnedProfileIds(db, 'labs', 'ownerUid', uid);
    } catch (_) {}
    const labIds = new Set([profileId, uid, ...ownedLabIds].filter(Boolean));
    for (const lid of labIds) {
      prefixes.add(`labs/${lid}/`);
      // NOTE: There is no lab_reports/{labId}/ prefix! Lab reports are stored as
      // lab_reports/{patientId}/{bookingId}/{uuid}.ext.
      // Specific report keys for this lab are collected via collectRoleSpecificS3ReportKeys()
      // and deleted specifically without touching any other reports or prefix.
    }
  }

  // 5. Medical store / pharmacy
  if (role === 'medicalStore' || role === 'pharmacy' || role === 'medical') {
    let ownedStoreIds = [];
    try {
      ownedStoreIds = await getOwnedProfileIds(db, 'medical_stores', 'ownerUid', uid);
    } catch (_) {}
    const storeIds = new Set([profileId, uid, ...ownedStoreIds].filter(Boolean));
    for (const sid of storeIds) {
      prefixes.add(`pharmacies/${sid}/`);
    }
  }

  // 6. Ambulance
  if (role === 'ambulance') {
    let ownedAmbIds = [];
    try {
      ownedAmbIds = await getOwnedProfileIds(db, 'ambulances', 'authUid', uid);
    } catch (_) {}
    const ambIds = new Set([profileId, uid, ...ownedAmbIds].filter(Boolean));
    for (const aid of ambIds) {
      prefixes.add(`ambulances/${aid}/`);
    }
  }

  return Array.from(prefixes);
}

/**
 * Collects exact S3 reportStorageKey values for roles that upload on behalf of another entity (e.g. lab uploading for patient).
 * Queries lab_bookings and lab_orders where labId is in providerIds.
 */
async function collectRoleSpecificS3ReportKeys(db, { role, profileId, uid }) {
  const keys = new Set();
  const reportRoles = ['lab', 'pharmacy', 'medicalStore', 'medical', 'ambulance'];
  if (!reportRoles.includes(role)) {
    return [];
  }

  let ownedIds = [];
  try {
    if (role === 'lab') {
      ownedIds = await getOwnedProfileIds(db, 'labs', 'ownerUid', uid);
    } else if (role === 'medicalStore' || role === 'pharmacy' || role === 'medical') {
      ownedIds = await getOwnedProfileIds(db, 'medical_stores', 'ownerUid', uid);
    } else if (role === 'ambulance') {
      ownedIds = await getOwnedProfileIds(db, 'ambulances', 'authUid', uid);
    }
  } catch (_) {}

  const providerIds = Array.from(new Set([profileId, uid, ...ownedIds].filter(Boolean)));

  for (const pid of providerIds) {
    try {
      // 1. lab_bookings
      const bookingsSnap = await db.collection('lab_bookings').where('labId', '==', pid).get();
      for (const doc of bookingsSnap.docs) {
        const data = doc.data() || {};
        const key = data.reportStorageKey;
        const provider = data.reportStorageProvider;
        if (key && typeof key === 'string' && (provider === 's3' || key.startsWith('lab_reports/'))) {
          keys.add(key.trim());
        }
      }

      // 2. lab_orders
      const ordersSnap = await db.collection('lab_orders').where('labId', '==', pid).get();
      for (const doc of ordersSnap.docs) {
        const data = doc.data() || {};
        const key = data.reportStorageKey;
        const provider = data.reportStorageProvider;
        if (key && typeof key === 'string' && (provider === 's3' || key.startsWith('lab_reports/'))) {
          keys.add(key.trim());
        }
      }
    } catch (err) {
      logger.warn('collectRoleSpecificS3ReportKeys query error', {
        providerId: pid,
        role,
        message: err?.message || 'unknown',
      });
    }
  }

  return Array.from(keys);
}

/**
 * Cleans up all S3 prefixes for a user. Best-effort: soft-fails per prefix.
 */
async function cleanupUserS3Prefixes(s3, bucketName, prefixes) {
  const failedS3Prefixes = [];
  for (const prefix of prefixes) {
    const res = await deleteS3PrefixVersions(s3, bucketName, prefix);
    if (!res.success) {
      failedS3Prefixes.push(prefix);
    }
  }
  return failedS3Prefixes;
}

async function countSuperAdmins(db) {
  const [a, b] = await Promise.all([
    db.collection('users').where('role', '==', 'super_admin').get(),
    db.collection('users').where('role', '==', 'superAdmin').get(),
  ]);
  const ids = new Set([...a.docs, ...b.docs].map((doc) => doc.id));
  return ids.size;
}

async function assertCanDeleteUser(db, uid, role) {
  if (role !== 'super_admin' && role !== 'superAdmin') return;
  const count = await countSuperAdmins(db);
  if (count <= 1) {
    throw new HttpsError(
      'failed-precondition',
      'Cannot delete the last Super Admin account.',
    );
  }
}

async function deleteAccountSupportData(db, { uid, email, mobileDigits }) {
  const deletes = [];

  await Promise.all([
    deleteWhere(db, 'in_app_notifications', 'recipientUid', uid),
    deleteWhere(db, 'promotedAds', 'providerId', uid),
  ]);

  if (email) {
    deletes.push(
      db.collection('otp_rate_limits').doc(`login_id_${hashKey(email)}`).delete().catch(() => {}),
    );
    for (const category of ABUSE_CATEGORIES) {
      deletes.push(
        db
          .collection('abuse_rate_limits')
          .doc(`${category}_id_${hashKey(email)}`)
          .delete()
          .catch(() => {}),
      );
    }
  }

  for (const category of ABUSE_CATEGORIES) {
    deletes.push(
      db
        .collection('abuse_rate_limits')
        .doc(`${category}_uid_${hashKey(uid)}`)
        .delete()
        .catch(() => {}),
    );
  }

  if (mobileDigits) {
    for (const otpRole of OTP_ROLES) {
      const key = mobileHash(otpRole, mobileDigits);
      deletes.push(
        db.collection('otp_challenges').doc(key).delete().catch(() => {}),
        db.collection('otp_verification_sessions').doc(key).delete().catch(() => {}),
      );
    }
  }

  await Promise.all(deletes);
}

async function deletePatientProfile(db, bucket, patientId) {
  if (!patientId) return;
  await deleteDocIfExists(db, db.collection('patients').doc(patientId));
  await deleteStoragePrefix(bucket, `patients/${patientId}/`);
}

async function deleteDoctorProfile(db, bucket, doctorId) {
  if (!doctorId) return;
  await deleteDocIfExists(db, db.collection('doctor_availability').doc(doctorId));
  await deleteDocIfExists(db, db.collection('doctors').doc(doctorId));
  await Promise.all([
    deleteStoragePrefix(bucket, `doctor_profiles/${doctorId}/`),
    deleteStoragePrefix(bucket, `doctors/${doctorId}/`),
  ]);
}

async function deleteMedicalStoreProfile(db, bucket, storeId) {
  if (!storeId) return;
  await deleteDocIfExists(db, db.collection('medical_stores').doc(storeId));
  await deleteStoragePrefix(bucket, `pharmacies/${storeId}/`);
}

async function deleteLabProfile(db, bucket, labId) {
  if (!labId) return;
  await deleteDocIfExists(db, db.collection('labs').doc(labId));
  await deleteStoragePrefix(bucket, `labs/${labId}/`);
}

async function deleteAmbulanceProfile(db, bucket, ambulanceId) {
  if (!ambulanceId) return;
  await deleteDocIfExists(db, db.collection('ambulances').doc(ambulanceId));
  await deleteStoragePrefix(bucket, `ambulances/${ambulanceId}/`);
}

async function deleteOwnedProfiles(db, bucket, collection, field, uid, deleteFn) {
  const normalizedUid = String(uid || '').trim();
  if (!normalizedUid) return;

  let lastDoc = null;
  while (true) {
    let query = db.collection(collection).where(field, '==', normalizedUid).limit(200);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      await deleteFn(db, bucket, doc.id);
    }

    if (snap.size < 200) break;
    lastDoc = snap.docs[snap.docs.length - 1];
  }
}

async function deleteRoleOwnedProfiles(db, bucket, uid) {
  await Promise.all([
    deleteOwnedProfiles(db, bucket, 'patients', 'ownerUid', uid, deletePatientProfile),
    deleteOwnedProfiles(db, bucket, 'doctors', 'ownerUid', uid, deleteDoctorProfile),
    deleteOwnedProfiles(
      db,
      bucket,
      'medical_stores',
      'ownerUid',
      uid,
      deleteMedicalStoreProfile,
    ),
    deleteOwnedProfiles(db, bucket, 'labs', 'ownerUid', uid, deleteLabProfile),
    deleteOwnedProfiles(db, bucket, 'ambulances', 'authUid', uid, deleteAmbulanceProfile),
  ]);
}

async function deleteRoleProfileData(db, bucket, role, profileId) {
  switch (role) {
    case 'patient':
      await deletePatientProfile(db, bucket, profileId);
      break;
    case 'doctor':
      await deleteDoctorProfile(db, bucket, profileId);
      break;
    case 'medicalStore':
    case 'medical':
    case 'pharmacy':
      await deleteMedicalStoreProfile(db, bucket, profileId);
      break;
    case 'lab':
      await deleteLabProfile(db, bucket, profileId);
      break;
    case 'ambulance':
      await deleteAmbulanceProfile(db, bucket, profileId);
      break;
    default:
      break;
  }
}

async function deletePersonalStorage(db, bucket, uid) {
  await Promise.all([
    deleteStoragePrefix(bucket, `verification_docs/${uid}/`),
    deleteStoragePrefix(bucket, `promoted_ads/${uid}/`),
  ]);
}

function readBoundSecret(secret, envName) {
  try {
    if (secret && typeof secret.value === 'function') {
      const bound = secret.value();
      if (bound) return String(bound).trim();
    }
  } catch (_) {}
  return String(process.env[envName] || '').trim();
}

function getSupabaseServiceConfig() {
  const url = String(process.env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
  const key = readBoundSecret(supabaseServiceRoleKey, 'SUPABASE_SERVICE_ROLE_KEY') ||
    readSupabaseServiceRoleKey({ required: false }) ||
    String(process.env.SUPABASE_SECRET_KEY || '').trim() ||
    String(process.env.SUPABASE_SERVICE_KEY || '').trim();
  if (!url || !key) return null;
  return { url, key };
}

function supabaseHeaders(key) {
  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
    Prefer: 'return=representation',
  };
}

async function supabaseRequest(config, method, pathAndQuery, body) {
  const doFetch = _testingSupabaseFetch || fetch;
  const resp = await doFetch(`${config.url}/rest/v1/${pathAndQuery}`, {
    method,
    headers: supabaseHeaders(config.key),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await resp.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_) {
    json = null;
  }
  if (!resp.ok) {
    const err = new Error(`Supabase ${method} ${pathAndQuery.split('?')[0]} failed (${resp.status})`);
    err.status = resp.status;
    throw err;
  }
  return json;
}

function addIds(set, rows, field) {
  if (!Array.isArray(rows)) return;
  for (const row of rows) {
    const value = String(row?.[field] || '').trim();
    if (value) set.add(value);
  }
}

/**
 * Best-effort PostgREST cleanup of this user's Supabase rows.
 * Uses service-role credentials when present; soft-fails per table.
 */
async function cleanupUserSupabaseRows({ uid, role, profileId }) {
  const failedSupabaseTables = [];
  const config = getSupabaseServiceConfig();
  if (!config) {
    return { skipped: true, failedSupabaseTables };
  }

  const recordFailure = (table, err) => {
    failedSupabaseTables.push(table);
    logger.warn('deleteMyAccount supabase cleanup failed', {
      table,
      uidHash: hashKey(uid).slice(0, 16),
      status: err?.status || 'unknown',
    });
  };

  const del = async (table, query) => {
    try {
      await supabaseRequest(config, 'DELETE', `${table}?${query}`);
    } catch (err) {
      recordFailure(table, err);
    }
  };

  const getRows = async (table, query, field) => {
    try {
      return await supabaseRequest(config, 'GET', `${table}?${query}&select=${field}`);
    } catch (err) {
      recordFailure(table, err);
      return [];
    }
  };

  let supabaseUserId = '';
  let supabaseProfileId = String(profileId || '').trim();
  let supabaseRole = String(role || '').trim();

  try {
    const rows = await supabaseRequest(
      config,
      'GET',
      `users?firebase_uid=eq.${encodeURIComponent(uid)}&select=id,profile_id,role`,
    );
    if (Array.isArray(rows) && rows[0]) {
      supabaseUserId = String(rows[0].id || '').trim();
      if (!supabaseProfileId) supabaseProfileId = String(rows[0].profile_id || '').trim();
      if (!supabaseRole) supabaseRole = String(rows[0].role || '').trim();
    }
  } catch (err) {
    recordFailure('users', err);
  }

  const patientIds = new Set();
  const doctorIds = new Set();
  const storeIds = new Set();
  const labIds = new Set();
  const ambulanceIds = new Set();

  if (supabaseRole === 'patient' && supabaseProfileId) patientIds.add(supabaseProfileId);
  if (supabaseRole === 'doctor' && supabaseProfileId) doctorIds.add(supabaseProfileId);
  if (
    (supabaseRole === 'medicalStore' || supabaseRole === 'medical' || supabaseRole === 'pharmacy')
    && supabaseProfileId
  ) {
    storeIds.add(supabaseProfileId);
  }
  if (supabaseRole === 'lab' && supabaseProfileId) labIds.add(supabaseProfileId);
  if (supabaseRole === 'ambulance' && supabaseProfileId) ambulanceIds.add(supabaseProfileId);

  if (supabaseUserId) {
    addIds(patientIds, await getRows('patients', `owner_uid=eq.${encodeURIComponent(supabaseUserId)}`, 'patient_id'), 'patient_id');
    addIds(doctorIds, await getRows('doctors', `owner_uid=eq.${encodeURIComponent(supabaseUserId)}`, 'doctor_id'), 'doctor_id');
    addIds(storeIds, await getRows('medical_stores', `owner_uid=eq.${encodeURIComponent(supabaseUserId)}`, 'store_id'), 'store_id');
    addIds(labIds, await getRows('labs', `owner_uid=eq.${encodeURIComponent(supabaseUserId)}`, 'lab_id'), 'lab_id');
    addIds(ambulanceIds, await getRows('ambulances', `auth_uid=eq.${encodeURIComponent(supabaseUserId)}`, 'ambulance_id'), 'ambulance_id');
  }

  // 1. Collect and delete deliveries and medicines (RESTRICT on prescriptions/patients/stores/doctors)
  const deliveryIds = new Set();
  for (const pid of patientIds) {
    addIds(deliveryIds, await getRows('pharmacy_deliveries', `patient_id=eq.${encodeURIComponent(pid)}`, 'delivery_id'), 'delivery_id');
  }
  for (const sid of storeIds) {
    addIds(deliveryIds, await getRows('pharmacy_deliveries', `store_id=eq.${encodeURIComponent(sid)}`, 'delivery_id'), 'delivery_id');
  }
  for (const did of doctorIds) {
    addIds(deliveryIds, await getRows('pharmacy_deliveries', `doctor_id=eq.${encodeURIComponent(did)}`, 'delivery_id'), 'delivery_id');
  }
  for (const delId of deliveryIds) {
    await del('pharmacy_delivery_medicines', `delivery_id=eq.${encodeURIComponent(delId)}`);
    await del('pharmacy_deliveries', `delivery_id=eq.${encodeURIComponent(delId)}`);
  }

  // 2. Lab orders & Lab bookings & Lab connections (RESTRICT on patients/doctors/labs)
  for (const pid of patientIds) {
    await del('lab_orders', `patient_id=eq.${encodeURIComponent(pid)}`);
    await del('lab_bookings', `patient_id=eq.${encodeURIComponent(pid)}`);
  }
  for (const lid of labIds) {
    await del('lab_orders', `lab_id=eq.${encodeURIComponent(lid)}`);
    await del('lab_bookings', `lab_id=eq.${encodeURIComponent(lid)}`);
    await del('lab_connections', `lab_id=eq.${encodeURIComponent(lid)}`);
  }
  for (const did of doctorIds) {
    await del('lab_orders', `doctor_id=eq.${encodeURIComponent(did)}`);
    await del('lab_connections', `doctor_id=eq.${encodeURIComponent(did)}`);
    await del('pharmacy_connections', `doctor_id=eq.${encodeURIComponent(did)}`);
  }
  for (const sid of storeIds) {
    await del('pharmacy_connections', `medical_store_id=eq.${encodeURIComponent(sid)}`);
  }

  // 3. Referrals (RESTRICT on patients/doctors)
  for (const pid of patientIds) {
    await del('referrals', `patient_id=eq.${encodeURIComponent(pid)}`);
  }
  for (const did of doctorIds) {
    await del('referrals', `from_doctor_id=eq.${encodeURIComponent(did)}`);
    await del('referrals', `to_doctor_id=eq.${encodeURIComponent(did)}`);
  }

  // 4. Prescriptions
  const prescriptionIds = new Set();
  for (const patientId of patientIds) {
    addIds(
      prescriptionIds,
      await getRows('prescriptions', `patient_id=eq.${encodeURIComponent(patientId)}`, 'prescription_id'),
      'prescription_id',
    );
  }
  for (const doctorId of doctorIds) {
    addIds(
      prescriptionIds,
      await getRows('prescriptions', `doctor_id=eq.${encodeURIComponent(doctorId)}`, 'prescription_id'),
      'prescription_id',
    );
  }

  for (const prescriptionId of prescriptionIds) {
    const q = `prescription_id=eq.${encodeURIComponent(prescriptionId)}`;
    await del('prescription_medicines', q);
    await del('prescription_investigations', q);
    await del('prescription_referrals', q);
    await del('prescriptions', q);
  }

  // 5. Patient records & relationships
  for (const patientId of patientIds) {
    const q = `patient_id=eq.${encodeURIComponent(patientId)}`;
    await del('health_records', q);
    await del('family_members', q);
    await del('review_votes', q);
    await del('reviews', q);
    await del('patient_doctor_links', q);
    await del('patient_care_team', q);
    await del('appointments', q);
    await del('ambulance_requests', q);
    await del('ambulance_broadcasts', q);
    await del('patients', q);
  }

  // 6. Doctor records & relationships
  for (const doctorId of doctorIds) {
    const q = `doctor_id=eq.${encodeURIComponent(doctorId)}`;
    await del('doctor_invites', q);
    await del('pharmacy_doctor_invites', q);
    await del('doctor_private', q);
    await del('doctor_availability', q);
    await del('doctor_facilities', q);
    await del('doctor_education', q);
    await del('doctor_blocked_dates', q);
    await del('patient_doctor_links', q);
    await del('patient_care_team', q);
    await del('reviews', q);
    await del('appointments', q);
    await del('doctors', q);
  }

  // 7. Store records
  for (const storeId of storeIds) {
    await del('pharmacy_doctor_invites', `store_id=eq.${encodeURIComponent(storeId)}`);
    await del('medical_stores', `store_id=eq.${encodeURIComponent(storeId)}`);
  }

  // 8. Lab records
  for (const labId of labIds) {
    await del('labs', `lab_id=eq.${encodeURIComponent(labId)}`);
  }

  // 9. Ambulance records
  for (const ambulanceId of ambulanceIds) {
    const q = `ambulance_id=eq.${encodeURIComponent(ambulanceId)}`;
    await del('ambulance_private_settings', q);
    await del('ambulance_invites', q);
    await del('ambulance_locations', `driver_id=eq.${encodeURIComponent(ambulanceId)}`);
    await del('ambulance_requests', `driver_id=eq.${encodeURIComponent(ambulanceId)}`);
    await del('ambulance_broadcasts', `accepted_driver_id=eq.${encodeURIComponent(ambulanceId)}`);
    await del('ambulances', q);
  }

  // 10. Support tickets & messages
  const ticketIds = new Set();
  for (const pid of patientIds) {
    addIds(ticketIds, await getRows('support_tickets', `patient_id=eq.${encodeURIComponent(pid)}`, 'ticket_id'), 'ticket_id');
  }
  for (const did of doctorIds) {
    addIds(ticketIds, await getRows('support_tickets', `doctor_id=eq.${encodeURIComponent(did)}`, 'ticket_id'), 'ticket_id');
  }
  for (const sid of storeIds) {
    addIds(ticketIds, await getRows('support_tickets', `store_id=eq.${encodeURIComponent(sid)}`, 'ticket_id'), 'ticket_id');
  }
  for (const lid of labIds) {
    addIds(ticketIds, await getRows('support_tickets', `lab_id=eq.${encodeURIComponent(lid)}`, 'ticket_id'), 'ticket_id');
  }
  for (const aid of ambulanceIds) {
    addIds(ticketIds, await getRows('support_tickets', `ambulance_id=eq.${encodeURIComponent(aid)}`, 'ticket_id'), 'ticket_id');
  }
  if (supabaseUserId) {
    addIds(ticketIds, await getRows('support_tickets', `user_id=eq.${encodeURIComponent(supabaseUserId)}`, 'ticket_id'), 'ticket_id');
  }
  for (const tid of ticketIds) {
    await del('support_ticket_messages', `ticket_id=eq.${encodeURIComponent(tid)}`);
    await del('support_tickets', `ticket_id=eq.${encodeURIComponent(tid)}`);
  }

  if (supabaseUserId) {
    await del('user_devices', `user_id=eq.${encodeURIComponent(supabaseUserId)}`);
  }
  await del('in_app_notifications', `recipient_uid=eq.${encodeURIComponent(uid)}`);

  // Anonymize payment records (PII minimization while retaining accounting audit history)
  try {
    await supabaseRequest(
      config,
      'PATCH',
      `razorpay_orders?user_uid=eq.${encodeURIComponent(uid)}`,
      { user_uid: null },
    );
  } catch (err) {
    recordFailure('razorpay_orders', err);
  }

  try {
    await supabaseRequest(config, 'DELETE', `users?firebase_uid=eq.${encodeURIComponent(uid)}`);
  } catch (deleteErr) {
    try {
      await supabaseRequest(
        config,
        'PATCH',
        `users?firebase_uid=eq.${encodeURIComponent(uid)}`,
        {
          display_name: 'Deleted User',
          email: `deleted-${uid}@deleted.invalid`,
          mobile: null,
          photo_url: null,
          deactivated: true,
          firebase_uid: null,
        },
      );
    } catch (patchErr) {
      recordFailure('users', patchErr || deleteErr);
    }
  }

  // TASK 1e: auth.users admin call removed (Firebase Auth is primary)

  return { skipped: false, failedSupabaseTables };
}

/**
 * Deletes only the authenticated user's personal/account data, then Auth.
 * Shared clinical/commerce/history records are intentionally preserved.
 * @param {string} uid Firebase Auth uid (must come from context.auth.uid)
 */
async function deleteMyAccountHandler(uid) {
  const normalizedUid = String(uid || '').trim();
  if (!normalizedUid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }

  const { isDoctorPatientSupabasePrimary } = require('./sync_flags');
  const isCutover = (await isDoctorPatientSupabasePrimary()) || process.env.FIRESTORE_FORBIDDEN === '1';

  if (isCutover) {
    let profile = null;
    try {
      profile = await resolveCallerIdentity({ uid: normalizedUid, forceSupabase: true });
    } catch (err) {
      // User not found in Supabase
    }

    if (!profile) {
      try {
        await getAuth().deleteUser(normalizedUid);
      } catch (err) {
        if (err?.code !== 'auth/user-not-found') {
          logger.error('deleteMyAccount auth cleanup failed for missing profile', {
            uid: normalizedUid,
            code: err?.code || 'unknown',
          });
          throw new HttpsError('internal', 'Could not delete account. Please try again.');
        }
      }
      return { ok: true, alreadyDeleted: true };
    }

    const role = String(profile.role || '').trim();
    const profileId = String(profile.profileId || profile.profile_id || '').trim();

    // S3 cleanup
    let failedS3Prefixes = [];
    try {
      const s3 = getS3Client();
      const s3Prefixes = [];
      if (profileId) {
        if (role === 'doctor') s3Prefixes.push(`doctor_profiles/${profileId}/`);
        if (role === 'patient') {
          s3Prefixes.push(`patient_profiles/${profileId}/`);
          s3Prefixes.push(`health_records/${profileId}/`);
        }
        if (role === 'lab') s3Prefixes.push(`lab_reports/${profileId}/`);
        if (role === 'medicalStore' || role === 'medical') s3Prefixes.push(`pharmacy_licenses/${profileId}/`);
        s3Prefixes.push(`promoted_ads/${profileId}/`);
      }
      s3Prefixes.push(`avatars/${normalizedUid}/`);
      failedS3Prefixes = await cleanupUserS3Prefixes(s3, S3_BUCKET, s3Prefixes);
    } catch (s3Err) {
      logger.warn('deleteMyAccount S3 cleanup unexpected failure (soft-fail)', {
        uid: normalizedUid,
        message: s3Err?.message || 'unknown',
      });
    }

    // Supabase row cleanup
    let failedSupabaseTables = [];
    try {
      const supabaseCleanup = await cleanupUserSupabaseRows({
        uid: normalizedUid,
        role,
        profileId,
      });
      failedSupabaseTables = supabaseCleanup.failedSupabaseTables || [];
    } catch (sbErr) {
      logger.warn('deleteMyAccount Supabase cleanup unexpected failure (soft-fail)', {
        uid: normalizedUid,
        message: sbErr?.message || 'unknown',
      });
    }

    // Delete Firebase Auth user LAST
    try {
      await getAuth().deleteUser(normalizedUid);
    } catch (authErr) {
      if (authErr?.code !== 'auth/user-not-found') {
        logger.error('deleteMyAccount Firebase Auth deletion failed', {
          uid: normalizedUid,
          code: authErr?.code || 'unknown',
        });
        throw new HttpsError('internal', 'Could not delete account. Please try again.');
      }
    }

    return {
      ok: true,
      supabase: true,
      failedS3Prefixes,
      failedSupabaseTables,
    };
  }

  const db = getFirestore();
  const bucket = getStorage().bucket();
  const userRef = db.collection('users').doc(normalizedUid);
  const userSnap = await userRef.get();

  if (!userSnap.exists) {
    try {
      await getAuth().deleteUser(normalizedUid);
    } catch (err) {
      if (err?.code !== 'auth/user-not-found') {
        logger.error('deleteMyAccount auth cleanup failed for missing profile', {
          uid: normalizedUid,
          code: err?.code || 'unknown',
        });
        throw new HttpsError('internal', 'Could not delete account. Please try again.');
      }
    }
    return { ok: true, alreadyDeleted: true };
  }

  const profile = userSnap.data() || {};
  const role = String(profile.role || '').trim();
  const profileId = String(profile.profileId || '').trim();
  const email = normalizeEmail(profile.email);
  const mobileDigits = normalizeMobileDigits(profile.mobile);

  await assertCanDeleteUser(db, normalizedUid, role);

  try {
    await deleteAccountSupportData(db, {
      uid: normalizedUid,
      email,
      mobileDigits,
    });
    await deletePersonalStorage(db, bucket, normalizedUid);

    if (profileId) {
      await deleteRoleProfileData(db, bucket, role, profileId);
    }

    await deleteRoleOwnedProfiles(db, bucket, normalizedUid);

    // S3 cleanup (best-effort, soft-fail per prefix/key)
    let failedS3Prefixes = [];
    let failedS3Keys = [];
    try {
      const s3 = getS3Client();
      const s3Prefixes = await resolveUserS3Prefixes(db, {
        uid: normalizedUid,
        role,
        profileId,
      });
      failedS3Prefixes = await cleanupUserS3Prefixes(s3, S3_BUCKET, s3Prefixes);

      // Collect specific S3 object keys (e.g. lab reports uploaded by this lab for patients)
      const specificReportKeys = await collectRoleSpecificS3ReportKeys(db, {
        role,
        profileId,
        uid: normalizedUid,
      });
      if (specificReportKeys.length > 0) {
        const keysRes = await deleteS3SpecificKeysVersions(s3, S3_BUCKET, specificReportKeys);
        if (!keysRes.success && keysRes.failedKeys) {
          failedS3Keys = keysRes.failedKeys;
        }
      }

      const totalFailed = [...failedS3Prefixes, ...failedS3Keys];
      if (totalFailed.length > 0) {
        logger.warn('deleteMyAccount: Some S3 items failed cleanup (soft-fail)', {
          uid: normalizedUid,
          failedS3Prefixes,
          failedS3Keys,
        });
      }
    } catch (s3Err) {
      logger.warn('deleteMyAccount S3 cleanup unexpected failure (soft-fail)', {
        uid: normalizedUid,
        message: s3Err?.message || 'unknown',
      });
    }

    let failedSupabaseTables = [];
    try {
      const supabaseCleanup = await cleanupUserSupabaseRows({
        uid: normalizedUid,
        role,
        profileId,
      });
      failedSupabaseTables = supabaseCleanup.failedSupabaseTables || [];
      if (failedSupabaseTables.length > 0) {
        logger.warn('deleteMyAccount: Some Supabase tables failed cleanup (soft-fail)', {
          uid: normalizedUid,
          failedSupabaseTables,
        });
      }
    } catch (supabaseErr) {
      failedSupabaseTables = ['supabase'];
      logger.warn('deleteMyAccount supabase cleanup unexpected failure (soft-fail)', {
        uid: normalizedUid,
        message: supabaseErr?.message || 'unknown',
      });
    }

    await deleteDocIfExists(db, userRef);

    await getAuth().deleteUser(normalizedUid);

    logger.info('deleteMyAccount completed', { uid: normalizedUid, role });
    const failedS3Total = [...failedS3Prefixes, ...failedS3Keys];
    return {
      ok: true,
      ...(failedS3Total.length > 0 ? { failedS3Prefixes: failedS3Total } : {}),
      ...(failedSupabaseTables.length > 0 ? { failedSupabaseTables } : {}),
    };
  } catch (err) {
    logger.error('deleteMyAccount failed', {
      uid: normalizedUid,
      role,
      code: err?.code || 'unknown',
      message: err?.message || 'unknown',
    });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('internal', 'Could not delete account. Please try again.');
  }
}

module.exports = {
  deleteMyAccountHandler,
  deleteS3PrefixVersions,
  deleteS3SpecificKeysVersions,
  collectRoleSpecificS3ReportKeys,
  resolveUserS3Prefixes,
  cleanupUserS3Prefixes,
  cleanupUserSupabaseRows,
  cleanupUserRedisKeys,
  setS3ClientForTesting,
  setSupabaseFetchForTesting,
  getS3Client,

  supabaseServiceRoleKey,
};
