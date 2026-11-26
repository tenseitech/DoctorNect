'use strict';

/**
 * Controls gateway audit log volume (OPS cost) without dropping security signals.
 * GATEWAY_AUDIT_SUCCESS_SAMPLE_RATE: 0.0–1.0 (default 1.0 = log all success responses).
 */

function resolveSuccessSampleRate() {
  const raw = parseFloat(String(process.env.GATEWAY_AUDIT_SUCCESS_SAMPLE_RATE || '1'));
  if (Number.isNaN(raw)) return 1;
  return Math.min(1, Math.max(0, raw));
}

function shouldEmitGatewayAuditLog({ statusCode, method, path } = {}) {
  const status = Number(statusCode) || 0;
  if (status >= 400) return true;
  if (String(method || '').toUpperCase() === 'OPTIONS') return false;
  const cleanPath = String(path || '').split('?')[0];
  if (cleanPath === '/livez' || cleanPath === '/readyz' || cleanPath === '/healthz') {
    return true;
  }
  const rate = resolveSuccessSampleRate();
  if (rate >= 1) return true;
  if (rate <= 0) return false;
  return Math.random() < rate;
}

module.exports = {
  resolveSuccessSampleRate,
  shouldEmitGatewayAuditLog,
};