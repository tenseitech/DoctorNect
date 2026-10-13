'use strict';

const crypto = require('crypto');

/**
 * Fixed UUID namespace for DoctorNect deterministic UUID v5 generation.
 * Matches RFC 4122 DNS namespace standard used across Supabase migrations and migration scripts.
 */
const DOCTORNECT_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

/**
 * Deterministically computes an RFC 4122 UUID v5 for a given Firebase UID using
 * the standard DoctorNect UUID namespace.
 *
 * Implemented using Node.js built-in `crypto` (zero external dependencies) so it runs
 * identically in Cloud Functions runtime, scripts, Edge bridges, and unit tests.
 *
 * @param {string} firebaseUid
 * @returns {string|null} Canonical UUID string or null if empty
 */
function toUserUuid(firebaseUid) {
  if (!firebaseUid || typeof firebaseUid !== 'string' || firebaseUid.trim().length === 0) {
    return null;
  }
  const str = firebaseUid.trim();
  const nsBuffer = Buffer.from(DOCTORNECT_NAMESPACE.replace(/-/g, ''), 'hex');
  const nameBuffer = Buffer.from(str, 'utf8');
  const hash = crypto.createHash('sha1').update(Buffer.concat([nsBuffer, nameBuffer])).digest();
  const b = Buffer.from(hash.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50; // version 5
  b[8] = (b[8] & 0x3f) | 0x80; // variant RFC 4122
  const hex = b.toString('hex');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join('-');
}

/**
 * Checks if an email string is synthetic (fallback domain).
 *
 * @param {string} email
 * @returns {boolean}
 */
function isSyntheticEmail(email) {
  if (!email || typeof email !== 'string') return false;
  const lower = email.trim().toLowerCase();
  return lower.endsWith('@signup.doctornect.app') || lower.endsWith('@users.doctornect.invalid');
}

/**
 * Checks if an error or status response represents a unique constraint violation on public.users.email (users_email_key).
 *
 * @param {Object|number|string} statusOrError
 * @param {string|Object} [bodyOrMessage='']
 * @returns {boolean}
 */
function isEmailUniqueViolation(statusOrError, bodyOrMessage = '') {
  if (typeof statusOrError === 'object' && statusOrError !== null) {
    const err = statusOrError;
    if (err.code === '23505' && (
      err.constraint === 'users_email_key' ||
      String(err.message || '').includes('users_email_key') ||
      String(err.detail || '').includes('email')
    )) {
      return true;
    }
    bodyOrMessage = err.body || err.message || '';
    statusOrError = err.status || err.statusCode || 0;
  }
  const bodyStr = typeof bodyOrMessage === 'string' ? bodyOrMessage : JSON.stringify(bodyOrMessage);
  const statusNum = Number(statusOrError);
  return (statusNum === 409) && (
    bodyStr.includes('users_email_key') ||
    (bodyStr.includes('23505') && bodyStr.includes('email')) ||
    bodyStr.includes('Key (email)=')
  );
}

/**
 * Builds synthetic email fallbacks.
 * index 0: <normalizedUid>@signup.doctornect.app
 * index 1: <userUuid>@signup.doctornect.app
 *
 * @param {string} uid
 * @param {number} [fallbackIndex=0]
 * @returns {string}
 */
function buildSyntheticEmail(uid, fallbackIndex = 0) {
  if (fallbackIndex === 0) {
    const normalized = String(uid || '').trim().replace(/[^a-zA-Z0-9_-]/g, '_').toLowerCase();
    return `${normalized}@signup.doctornect.app`;
  }
  const uuid = toUserUuid(uid);
  return `${uuid}@signup.doctornect.app`;
}

/**
 * Deterministic hash of UID for privacy-safe structured logging (first 16 hex chars).
 *
 * @param {string} uid
 * @returns {string|null}
 */
function hashUid(uid) {
  if (!uid) return null;
  return crypto.createHash('sha256').update(String(uid)).digest('hex').slice(0, 16);
}

/**
 * Shared helper to execute user sync/upsert with email collision fallback logic.
 * Used identically by backfill_users_to_supabase.js and cross_role_sync.js (syncFirestoreUserToSupabase).
 *
 * Guarantees:
 * - Insert path: tries real email; on 409/23505 users_email_key, retries once with synthetic email,
 *   and if that conflicts, retries with uuid-based email.
 * - Update path: if row already exists, never overwrites a real email with a synthetic one.
 *   If update with real email collides, omits email from PATCH to preserve existing value.
 * - Privacy: all warning logs contain uidHash and reason only; strictly zero raw PII.
 *
 * @param {Object} params
 * @param {string} params.uid - Firebase UID
 * @param {Object} params.row - public.users payload fields (role, email, display_name, etc.)
 * @param {string} params.createdAt - ISO timestamp
 * @param {string} params.deterministicId - UUID
 * @param {Object|null} params.existingUser - Row from DB if already exists (must include .email)
 * @param {Function} params.patchFn - async (payload) => Response/result
 * @param {Function} params.postFn - async (payload) => Response/result
 * @param {Function} [params.logger] - (msg) => void
 * @param {Object} [params.counts] - { emailFallbackSynthetic: 0, emailKeptOnUpdate: 0 }
 * @returns {Promise<{ action: 'updated'|'inserted', emailFallbackSynthetic?: boolean, emailKeptOnUpdate?: boolean }>}
 */
async function executeUserSyncWithEmailFallback({
  uid,
  row,
  createdAt,
  deterministicId,
  existingUser,
  patchFn,
  postFn,
  logger = console.warn,
  counts,
}) {
  const uidHash = hashUid(uid);

  // Helper for structured logging with strictly zero PII
  const logStructuredWarn = (action, reason) => {
    try {
      logger(JSON.stringify({
        severity: 'WARNING',
        category: 'sync',
        action,
        uidHash,
        reason,
      }));
    } catch (_) {}
  };

  // UPDATE PATH: row already exists by firebase_uid or deterministic id
  if (existingUser) {
    const existingEmail = existingUser.email ? String(existingUser.email).trim().toLowerCase() : '';
    const incomingEmail = row.email ? String(row.email).trim().toLowerCase() : '';

    let payload = { ...row };
    let keepExistingEmail = false;

    // Rule: Never overwrite an existing real email with a synthetic one
    if (existingEmail && !isSyntheticEmail(existingEmail) && incomingEmail && isSyntheticEmail(incomingEmail)) {
      keepExistingEmail = true;
    }

    if (keepExistingEmail) {
      const { email: _omit, ...rest } = payload;
      payload = rest;
      if (counts) counts.emailKeptOnUpdate = (counts.emailKeptOnUpdate || 0) + 1;
      logStructuredWarn('email_kept_on_update', 'Preserved existing real email instead of overwriting with synthetic email');
      await patchFn(payload);
      return { action: 'updated', emailKeptOnUpdate: true };
    }

    // Try normal patch with incoming email
    try {
      await patchFn(payload);
      return { action: 'updated' };
    } catch (err) {
      if (isEmailUniqueViolation(err)) {
        // If the new email would collide, omit email from PATCH so existing value is kept
        const { email: _omit, ...rest } = payload;
        if (counts) counts.emailKeptOnUpdate = (counts.emailKeptOnUpdate || 0) + 1;
        logStructuredWarn('email_collision_update_kept', 'users_email_key collision on update; omitting email to preserve existing value');
        await patchFn(rest);
        return { action: 'updated', emailKeptOnUpdate: true };
      }
      throw err;
    }
  }

  // INSERT PATH: row does not exist
  const insertPayload = {
    id: deterministicId,
    created_at: createdAt,
    ...row,
  };

  try {
    await postFn(insertPayload);
    return { action: 'inserted' };
  } catch (err) {
    if (!isEmailUniqueViolation(err)) {
      throw err;
    }

    // 409 / 23505 users_email_key collision on insert: Retry once with synthetic email ${normalizedUid}@signup.doctornect.app
    const fallback1 = buildSyntheticEmail(uid, 0);
    insertPayload.email = fallback1;
    logStructuredWarn('email_collision_insert_synthetic', 'users_email_key collision on insert; retrying with synthetic email');

    try {
      await postFn(insertPayload);
      if (counts) counts.emailFallbackSynthetic = (counts.emailFallbackSynthetic || 0) + 1;
      return { action: 'inserted', emailFallbackSynthetic: true };
    } catch (err2) {
      if (!isEmailUniqueViolation(err2)) {
        throw err2;
      }

      // If synthetic also conflicts, use ${toUserUuid(uid)}@signup.doctornect.app
      const fallback2 = buildSyntheticEmail(uid, 1);
      insertPayload.email = fallback2;
      logStructuredWarn('email_collision_insert_uuid', 'users_email_key collision on synthetic; retrying with uuid-based email');

      await postFn(insertPayload);
      if (counts) counts.emailFallbackSynthetic = (counts.emailFallbackSynthetic || 0) + 1;
      return { action: 'inserted', emailFallbackSynthetic: true };
    }
  }
}

module.exports = {
  DOCTORNECT_NAMESPACE,
  toUserUuid,
  isSyntheticEmail,
  isEmailUniqueViolation,
  buildSyntheticEmail,
  hashUid,
  executeUserSyncWithEmailFallback,
};
