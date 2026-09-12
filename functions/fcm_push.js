const { getMessaging } = require('firebase-admin/messaging');
const { FieldValue } = require('firebase-admin/firestore');

const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

function stringifyData(data) {
  const out = {};
  for (const [key, value] of Object.entries(data || {})) {
    if (value == null) continue;
    out[key] = String(value);
  }
  return out;
}

/**
 * Sends a high-priority FCM notification when the profile document has an fcmToken.
 *
 * @param {import('firebase-admin/firestore').Firestore} db
 * @param {object} options
 * @param {string} options.collection Firestore collection name (e.g. patients, doctors)
 * @param {string} options.docId Document id within collection
 * @param {string} options.title Notification title
 * @param {string} options.body Notification body
 * @param {Record<string, string|number|boolean|null|undefined>} [options.data] FCM data payload
 * @param {string} options.androidChannelId Android notification channel id
 * @param {string} [options.logLabel] Label for error logs
 * @param {(db: import('firebase-admin/firestore').Firestore) => Promise<{ token: string, invalidateTokenRef: import('firebase-admin/firestore').DocumentReference } | null>} [options.resolveToken] Optional custom token lookup (ambulance private/settings)
 * @returns {Promise<boolean>} true when a message was sent
 */
async function sendFcmIfTokenExists(db, {
  collection,
  docId,
  title,
  body,
  data = {},
  androidChannelId,
  logLabel,
  resolveToken,
}) {
  const label = logLabel || `${collection}/${docId}`;

  let token;
  let invalidateTokenRef;

  if (resolveToken) {
    const resolved = await resolveToken(db);
    if (!resolved?.token) return false;
    token = resolved.token;
    invalidateTokenRef = resolved.invalidateTokenRef;
  } else {
    const ref = db.collection(collection).doc(docId);
    const snap = await ref.get();
    if (!snap.exists) return false;
    token = snap.data()?.fcmToken;
    invalidateTokenRef = ref;
  }

  if (!token) return false;

  try {
    await getMessaging().send({
      token,
      notification: { title, body },
      data: stringifyData(data),
      android: {
        priority: 'high',
        notification: {
          channelId: androidChannelId,
          priority: 'high',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    });
    return true;
  } catch (err) {
    const code = err?.code || err?.errorInfo?.code;
    if (INVALID_TOKEN_CODES.has(code) && invalidateTokenRef) {
      await invalidateTokenRef.set(
        {
          fcmToken: FieldValue.delete(),
          fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    console.error(`FCM send failed for ${label}`, err);
    return false;
  }
}

async function resolveAmbulanceDriverToken(db, driverId) {
  const driverSnap = await db.collection('ambulances').doc(driverId).get();
  if (!driverSnap.exists) return null;

  const driver = driverSnap.data();
  let fcmToken = driver?.fcmToken;
  const privateRef = db
    .collection('ambulances')
    .doc(driverId)
    .collection('private')
    .doc('settings');

  if (!fcmToken) {
    const privateSnap = await privateRef.get();
    fcmToken = privateSnap.data()?.fcmToken;
  }
  if (!fcmToken) return null;

  return {
    token: fcmToken,
    invalidateTokenRef: privateRef,
  };
}

module.exports = {
  sendFcmIfTokenExists,
  resolveAmbulanceDriverToken,
};
