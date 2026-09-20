'use strict';

const crypto = require('crypto');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const { logger } = require('firebase-functions');
const { HttpsError } = require('firebase-functions/v2/https');

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
    await deleteDocIfExists(db, userRef);

    await getAuth().deleteUser(normalizedUid);

    logger.info('deleteMyAccount completed', { uid: normalizedUid, role });
    return { ok: true };
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
};
