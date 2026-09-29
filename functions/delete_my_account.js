'use strict';

const crypto = require('crypto');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const { logger } = require('firebase-functions');
const { HttpsError } = require('firebase-functions/v2/https');
const {
  S3Client,
  ListObjectVersionsCommand,
  DeleteObjectsCommand,
} = require('@aws-sdk/client-s3');

const S3_BUCKET = process.env.S3_BUCKET || 'doctornect';
let _testingS3Client = null;

function setS3ClientForTesting(client) {
  _testingS3Client = client;
}

function getS3Client() {
  if (_testingS3Client) return _testingS3Client;
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

const OTP_ROLES = ['patient', 'doctor', 'medicalStore', 'lab', 'ambulance'];
const ABUSE_CATEGORIES = ['api', 'login', 'signup', 'ai', 'scrape', 'payment'];

function hashKey(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

function mobileHash(role, digits) {
  return crypto.createHash('sha256').update(`${role}:${digits}`).digest('hex');
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
  const isProvider = ['doctor', 'lab', 'pharmacy', 'medicalStore', 'ambulance'].includes(role);
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
      prefixes.add(`lab_reports/${lid}/`); // Lab's own report prefix
      // NOTE: We do NOT delete health_records/ or other patients' lab_reports/{otherPatientId}/!
    }
  }

  // 5. Medical store / pharmacy
  if (role === 'medicalStore' || role === 'pharmacy') {
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

    // S3 cleanup (best-effort, soft-fail per prefix)
    let failedS3Prefixes = [];
    try {
      const s3 = getS3Client();
      const s3Prefixes = await resolveUserS3Prefixes(db, {
        uid: normalizedUid,
        role,
        profileId,
      });
      failedS3Prefixes = await cleanupUserS3Prefixes(s3, S3_BUCKET, s3Prefixes);
      if (failedS3Prefixes.length > 0) {
        logger.warn('deleteMyAccount: Some S3 prefixes failed cleanup (soft-fail)', {
          uid: normalizedUid,
          failedS3Prefixes,
        });
      }
    } catch (s3Err) {
      logger.warn('deleteMyAccount S3 cleanup unexpected failure (soft-fail)', {
        uid: normalizedUid,
        message: s3Err?.message || 'unknown',
      });
    }

    await deleteDocIfExists(db, userRef);

    await getAuth().deleteUser(normalizedUid);

    logger.info('deleteMyAccount completed', { uid: normalizedUid, role });
    return {
      ok: true,
      ...(failedS3Prefixes.length > 0 ? { failedS3Prefixes } : {}),
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
  resolveUserS3Prefixes,
  cleanupUserS3Prefixes,
  setS3ClientForTesting,
  getS3Client,
};
