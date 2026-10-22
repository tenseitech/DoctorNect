require('./firestore_forbidden_guard');
'use strict';

const { FieldValue } = require('firebase-admin/firestore');
const { isDoctorPatientSupabasePrimary } = require('./sync_flags');
const { getSupabaseAdminClient } = require('./caller_identity');

let _getMessaging;
let _testingMessaging = null;

function setMessagingForTesting(messaging) {
  _testingMessaging = messaging;
}

function resolveMessaging() {
  if (_testingMessaging) return _testingMessaging;
  if (!_getMessaging) {
    _getMessaging = require('firebase-admin/messaging').getMessaging;
  }
  return _getMessaging();
}

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
 * Sends a high-priority FCM notification.
 * When cutover flag is ON, reads device tokens from Supabase public.user_devices via service role.
 * When cutover flag is OFF, reads from Firestore document.
 *
 * @param {import('firebase-admin/firestore').Firestore} db
 * @param {object} options
 * @param {string} options.collection Collection name (e.g. patients, doctors, ambulances)
 * @param {string} options.docId Document id / profile id
 * @param {string} [options.userId] Optional explicit user id (Firebase UID)
 * @param {string} options.title Notification title
 * @param {string} options.body Notification body
 * @param {Record<string, any>} [options.data] FCM data payload
 * @param {string} options.androidChannelId Android notification channel id
 * @param {string} [options.logLabel] Label for error logs
 * @param {Function} [options.resolveToken] Optional custom token lookup (Firestore legacy)
 * @param {boolean} [options.forceSupabase] Force Supabase lookup
 * @param {object} [options.supabaseClient] Supabase client override for tests
 * @returns {Promise<boolean>} true when a message was sent
 */
async function sendFcmIfTokenExists(db, {
  collection,
  docId,
  userId,
  title,
  body,
  data = {},
  androidChannelId,
  logLabel,
  resolveToken,
  forceSupabase = false,
  supabaseClient = null,
}) {
  const label = logLabel || `${collection}/${docId}`;
  const useSupabase = forceSupabase || (await isDoctorPatientSupabasePrimary());

  if (useSupabase) {
    const sb = supabaseClient || getSupabaseAdminClient();
    if (!sb) {
      console.warn(`[fcm_push] Supabase admin client not available for ${label}`);
      return false;
    }

    let targetUserId = userId;
    if (!targetUserId) {
      if (collection === 'users') {
        targetUserId = docId;
      } else {
        const { data: userRow } = await sb
          .from('users')
          .select('id')
          .or(`id.eq.${docId},profile_id.eq.${docId}`)
          .maybeSingle();
        targetUserId = userRow?.id || docId;
      }
    }

    const { data: devices, error } = await sb
      .from('user_devices')
      .select('id, fcm_token')
      .eq('user_id', targetUserId);

    if (error || !devices || devices.length === 0) {
      return false;
    }

    let sentAny = false;
    const messaging = resolveMessaging();

    for (const device of devices) {
      const token = device.fcm_token;
      if (!token) continue;

      try {
        await messaging.send({
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
        sentAny = true;
      } catch (err) {
        const code = err?.code || err?.errorInfo?.code;
        if (INVALID_TOKEN_CODES.has(code)) {
          await sb.from('user_devices').delete().eq('id', device.id);
        }
        console.error(`FCM send failed for ${label} (token ${token.slice(0, 8)}...)`, err?.message || err);
      }
    }

    return sentAny;
  }

  // Legacy Firestore path
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
    await resolveMessaging().send({
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

async function resolveAmbulanceDriverToken(db, driverId, { forceSupabase = false, supabaseClient = null } = {}) {
  const useSupabase = forceSupabase || (await isDoctorPatientSupabasePrimary());
  if (useSupabase) {
    const sb = supabaseClient || getSupabaseAdminClient();
    if (!sb) return null;
    const { data: userRow } = await sb
      .from('users')
      .select('id')
      .or(`id.eq.${driverId},profile_id.eq.${driverId}`)
      .maybeSingle();
    const uid = userRow?.id || driverId;
    const { data: devices } = await sb
      .from('user_devices')
      .select('id, fcm_token')
      .eq('user_id', uid)
      .limit(1);
    if (!devices || devices.length === 0) return null;
    return { token: devices[0].fcm_token };
  }

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
  setMessagingForTesting,
};
