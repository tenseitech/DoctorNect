'use strict';

/** Client-safe JWT verification errors from token_verifier / JWKS (no secrets). */
const SAFE_JWT_MESSAGE = /^(Invalid token |Token |Malformed JWT|Malformed jwt|Invalid JWT)/i;

const SENSITIVE_MESSAGE =
  /firebase admin unavailable|application default credentials|service account key|cannot verify token revocation|revocation check failed/i;

/**
 * Maps internal auth verification errors to client-safe messages (no stack traces or infra details).
 */
function clientAuthErrorMessage(err) {
  const raw = String(err?.message || '').trim();
  if (!raw) {
    return 'Authentication failed: invalid or expired token.';
  }
  if (SENSITIVE_MESSAGE.test(raw)) {
    return 'Authentication failed.';
  }
  if (SAFE_JWT_MESSAGE.test(raw) || /unable to find public key/i.test(raw)) {
    return raw;
  }
  if (/revoked/i.test(raw)) {
    return 'Authentication failed: token has been revoked.';
  }
  if (/expired/i.test(raw)) {
    return 'Authentication failed: token has expired.';
  }
  return 'Authentication failed: invalid or expired token.';
}

module.exports = {
  clientAuthErrorMessage,
};