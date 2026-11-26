'use strict';

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

/** Ids interpolated into PostgREST .or() filters must be plain identifiers. */
const SAFE_ID_RE = /^[A-Za-z0-9_\-:.]{1,128}$/;

function stringifyData(data) {
  const out = {};
  for (const [key, value] of Object.entries(data || {})) {
    if (value == null) continue;
    out[key] = String(value);
  }
  return out;
}

async function resolveUserIdForProfile(sb, profileOrUserId) {
  if (!SAFE_ID_RE.test(String(profileOrUserId || ''))) return null;
  const { data: userRow } = await sb
    .from('users')
    .select('id')
    .or(`id.eq.${profileOrUserId},profile_id.eq.${profileOrUserId}`)
    .maybeSingle();
  return userRow?.id || profileOrUserId;
}

/**
 * Sends a high-priority FCM notification to every device registered for the user
 * (public.user_devices). Invalid tokens are pruned. Never logs token material.
 *
 * @param {null} _unusedDb kept for call-site compatibility
 * @param {object} options
 * @param {string} options.collection Logical owner type (users, patients, doctors, ambulances)
 * @param {string} options.docId Profile id or user id
 * @param {string} [options.userId] Explicit Firebase UID
 * @returns {Promise<boolean>} true when a message was sent
 */
async function sendFcmIfTokenExists(_unusedDb, {
  collection,
  docId,
  userId,
  title,
  body,
  data = {},
  androidChannelId,
  logLabel,
  supabaseClient = null,
}) {
  const label = logLabel || `${collection}`;
  const sb = supabaseClient || getSupabaseAdminClient(userId || null);
  if (!sb) {
    console.warn(`[fcm_push] database client not available for ${label}`);
    return false;
  }

  let targetUserId = userId;
  if (!targetUserId) {
    targetUserId = collection === 'users' ? docId : await resolveUserIdForProfile(sb, docId);
  }
  if (!targetUserId || !SAFE_ID_RE.test(String(targetUserId))) {
    return false;
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
      console.error(`FCM send failed for ${label}`, code || err?.message || 'unknown');
    }
  }

  return sentAny;
}

async function resolveAmbulanceDriverToken(_unusedDb, driverId, { supabaseClient = null } = {}) {
  const sb = supabaseClient || getSupabaseAdminClient();
  if (!sb) return null;
  const uid = await resolveUserIdForProfile(sb, driverId);
  if (!uid) return null;
  const { data: devices } = await sb
    .from('user_devices')
    .select('id, fcm_token')
    .eq('user_id', uid)
    .limit(1);
  if (!devices || devices.length === 0) return null;
  return { token: devices[0].fcm_token };
}

module.exports = {
  sendFcmIfTokenExists,
  resolveAmbulanceDriverToken,
  setMessagingForTesting,
};
