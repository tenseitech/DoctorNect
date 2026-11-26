'use strict';

/**
 * Centralized redaction for operational logs (OPS-02).
 * Safe for Gateway, Functions, and scripts — no secrets/PHI in log strings.
 */

const SENSITIVE_KEY_PATTERN = /^(password|passwd|pwd|otp|token|refresh_?token|access_?token|id_?token|authorization|apikey|api_key|secret|jwt|bearer|ssn|aadhaar|prescription|diagnosis|lab_report|medical_record|patient_name|phone|mobile|email)$/i;

const BEARER_PATTERN = /Bearer\s+[A-Za-z0-9\-._~+/]+=*/gi;
const JWT_PATTERN = /eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g;
const PHONE_PATTERN = /(\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}/g;

function redactString(input, { replacement = '[REDACTED]' } = {}) {
  let s = String(input ?? '');
  if (!s) return s;
  s = s.replace(BEARER_PATTERN, `Bearer ${replacement}`);
  s = s.replace(JWT_PATTERN, replacement);
  s = s.replace(PHONE_PATTERN, replacement);
  if (s.length > 4000) {
    s = `${s.slice(0, 4000)}…[TRUNCATED]`;
  }
  return s;
}

function redactObject(value, { depth = 0, maxDepth = 6 } = {}) {
  if (depth > maxDepth) return '[TRUNCATED]';
  if (value === null || value === undefined) return value;
  if (typeof value === 'string') return redactString(value);
  if (typeof value !== 'object') return value;
  if (Array.isArray(value)) {
    return value.map((item) => redactObject(item, { depth: depth + 1, maxDepth }));
  }
  const out = {};
  for (const [key, val] of Object.entries(value)) {
    if (SENSITIVE_KEY_PATTERN.test(key)) {
      out[key] = '[REDACTED]';
    } else {
      out[key] = redactObject(val, { depth: depth + 1, maxDepth });
    }
  }
  return out;
}

function operationalLogEnvelope({
  service,
  event,
  severity = 'INFO',
  outcome = null,
  operation = null,
  requestId = null,
  durationMs = null,
  errorClassification = null,
  detail = null,
  extra = {},
} = {}) {
  const env = String(process.env.APP_ENV || process.env.NODE_ENV || 'staging').toLowerCase();
  const entry = {
    timestamp: new Date().toISOString(),
    service: service || 'unknown',
    environment: env,
    severity,
    event: event || 'ops_event',
    outcome,
    operation,
    request_id: requestId || null,
    duration_ms: durationMs != null ? Math.round(durationMs * 10) / 10 : null,
    error_classification: errorClassification,
  };
  if (detail != null) {
    entry.detail = typeof detail === 'string' ? redactString(detail) : redactObject(detail);
  }
  if (extra && typeof extra === 'object') {
    Object.assign(entry, redactObject(extra));
  }
  return entry;
}

function writeOperationalLog(entry, { stream = 'stdout' } = {}) {
  const line = `${JSON.stringify(entry)}\n`;
  if (stream === 'stderr' || entry.severity === 'ERROR' || entry.severity === 'CRITICAL') {
    process.stderr.write(line);
  } else {
    process.stdout.write(line);
  }
}

module.exports = {
  redactString,
  redactObject,
  operationalLogEnvelope,
  writeOperationalLog,
  SENSITIVE_KEY_PATTERN,
};