'use strict';

/**
 * Compute gateway SLI rollups from newline-delimited JSON audit logs (local/staging only).
 */

function parseAuditLines(text) {
  return String(text || '')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('{'))
    .map((l) => {
      try {
        return JSON.parse(l);
      } catch (_) {
        return null;
      }
    })
    .filter(Boolean)
    .filter((e) => e.event === 'api_request');
}

function rollupGatewaySli(lines) {
  const events = parseAuditLines(lines);
  if (events.length === 0) {
    return { count: 0, availability: null, error_rate: null, p95_latency_ms: null };
  }
  const statuses = events.map((e) => Number(e.status) || 0);
  const latencies = events.map((e) => Number(e.latency_ms) || 0).sort((a, b) => a - b);
  const success = statuses.filter((s) => s > 0 && s < 500).length;
  const errors5xx = statuses.filter((s) => s >= 500).length;
  const p95Index = Math.min(latencies.length - 1, Math.floor(latencies.length * 0.95));
  return {
    count: events.length,
    availability: success / events.length,
    error_rate_5xx: errors5xx / events.length,
    p95_latency_ms: latencies[p95Index] ?? null,
    measurement: 'static_log_rollup',
  };
}

module.exports = {
  parseAuditLines,
  rollupGatewaySli,
};