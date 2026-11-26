'use strict';

/**
 * Error summary that is safe for Cloud Logging: no stack, no PostgREST `details` / `hint`
 * (they can echo row values such as phone numbers or medical text), and long digit runs in the
 * message are masked. Use instead of passing a raw error object to console.error.
 */
function safeErrorForLog(err) {
  if (err == null) return { message: String(err) };
  const e = typeof err === 'object' ? err : { message: String(err) };
  const message = String(e.message || '')
    .replace(/\d{6,}/g, (m) => `***${m.slice(-2)}`)
    .slice(0, 300);
  const out = { name: e.name || undefined, code: e.code || undefined, message };
  if (e.status || e.httpErrorCode) out.status = e.status || (e.httpErrorCode && e.httpErrorCode.status);
  return out;
}

module.exports = { safeErrorForLog };
