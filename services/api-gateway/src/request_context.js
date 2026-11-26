'use strict';

const crypto = require('node:crypto');

const REQUEST_ID_HEADER = 'x-request-id';

/**
 * Resolve or mint a correlation id for gateway request tracing (REL-10).
 */
function resolveRequestId(req, headers = req?.headers || {}) {
  const incoming = String(headers[REQUEST_ID_HEADER] || headers['X-Request-Id'] || '').trim();
  if (incoming.length >= 8 && incoming.length <= 128 && /^[\w-]+$/.test(incoming)) {
    return incoming;
  }
  return crypto.randomBytes(12).toString('hex');
}

module.exports = {
  REQUEST_ID_HEADER,
  resolveRequestId,
};