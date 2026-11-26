'use strict';

/**
 * Structured OTP callable error logging — never omit MSG91 http status / body on failures.
 */

function redactMsg91Body(raw) {
  let s = String(raw == null ? '' : raw).slice(0, 800);
  s = s.replace(/\b\d{10}\b/g, '******');
  s = s.replace(/(authkey|auth_key|password|secret)(["':\s=]+)[^"'\s,}]+/gi, '$1$2[masked]');
  return s;
}

function logOtpCallableError(callable, err, context = {}) {
  const payload = {
    callable,
    ...context,
    errorCode: err?.code || err?.name || 'Error',
    errorMessage: err?.message || String(err),
    httpStatus: err?.httpStatus ?? null,
    msg91ResponseBody:
      err?.responseBody != null && err?.responseBody !== ''
        ? redactMsg91Body(err.responseBody)
        : null,
    stackPreview: String(err?.stack || '')
      .split('\n')
      .slice(0, 5)
      .join('\n'),
  };
  console.error(`[${callable}] failure detail`, payload);
  return payload;
}

module.exports = {
  logOtpCallableError,
  redactMsg91Body,
};