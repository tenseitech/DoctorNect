'use strict';

const crypto = require('crypto');

function normalizeLineEndings(content) {
  if (typeof content !== 'string') {
    return content;
  }
  return content.replace(/\r\n/g, '\n');
}

/** Canonical checksum: UTF-8 bytes after CRLF → LF normalization (used for new ledger rows). */
function computeChecksum(content) {
  const normalized = normalizeLineEndings(content);
  return crypto.createHash('sha256').update(normalized, 'utf8').digest('hex');
}

/** Pre-normalization checksum: raw file bytes as read (staging ledger rows applied on Windows). */
function computeLegacyRawChecksum(content) {
  return crypto.createHash('sha256').update(content, 'utf8').digest('hex');
}

function ledgerChecksumMatches(content, ledgerChecksum) {
  if (!ledgerChecksum || ledgerChecksum === 'legacy_supabase') {
    return true;
  }
  const normalized = computeChecksum(content);
  if (ledgerChecksum === normalized) {
    return true;
  }
  return ledgerChecksum === computeLegacyRawChecksum(content);
}

module.exports = {
  normalizeLineEndings,
  computeChecksum,
  computeLegacyRawChecksum,
  ledgerChecksumMatches,
};
