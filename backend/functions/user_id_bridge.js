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

module.exports = {
  DOCTORNECT_NAMESPACE,
  toUserUuid,
};
