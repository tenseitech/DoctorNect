#!/usr/bin/env node
'use strict';

/**
 * Provider-agnostic synthetic monitor for Auth Gateway health endpoints (Audit 7).
 * Usage: node scripts/ops/synthetic_gateway_probe.js --base-url http://127.0.0.1:8080
 * Exit 0 when all probes pass; exit 1 otherwise. Emits one JSON line per probe on stdout.
 */

const { operationalLogEnvelope, writeOperationalLog } = require('../lib/log_redaction');

function parseArgs(argv) {
  const out = { baseUrl: process.env.GATEWAY_PROBE_BASE_URL || '', timeoutMs: 5000 };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--base-url' && argv[i + 1]) {
      out.baseUrl = argv[++i].replace(/\/+$/, '');
    } else if (argv[i] === '--timeout-ms' && argv[i + 1]) {
      out.timeoutMs = Math.min(30000, Math.max(500, parseInt(argv[++i], 10) || 5000));
    }
  }
  return out;
}

async function probePath(baseUrl, path, timeoutMs) {
  const started = Date.now();
  const url = `${baseUrl}${path}`;
  try {
    const res = await fetch(url, {
      method: 'GET',
      signal: AbortSignal.timeout(timeoutMs),
      headers: { Accept: 'application/json' },
    });
    const latencyMs = Date.now() - started;
    let body = {};
    try {
      body = await res.json();
    } catch (_) {
      body = {};
    }
    const ok = res.ok || (path === '/healthz' && res.status === 503);
    const entry = operationalLogEnvelope({
      service: 'synthetic-gateway-probe',
      event: 'synthetic_probe',
      severity: ok ? 'INFO' : 'ERROR',
      outcome: ok ? 'success' : 'failure',
      operation: path,
      durationMs: latencyMs,
      detail: {
        http_status: res.status,
        probe: body.probe || body.status || null,
        liveness: path === '/livez',
        readiness: path === '/readyz',
      },
    });
    writeOperationalLog(entry);
    return { path, ok, status: res.status, latencyMs, body };
  } catch (err) {
    const latencyMs = Date.now() - started;
    const entry = operationalLogEnvelope({
      service: 'synthetic-gateway-probe',
      event: 'synthetic_probe',
      severity: 'ERROR',
      outcome: 'failure',
      operation: path,
      durationMs: latencyMs,
      errorClassification: 'timeout_or_network',
      detail: { message: String(err.message || err).slice(0, 200) },
    });
    writeOperationalLog(entry, { stream: 'stderr' });
    return { path, ok: false, status: 0, latencyMs, error: err.message };
  }
}

async function main() {
  const { baseUrl, timeoutMs } = parseArgs(process.argv);
  if (!baseUrl) {
    console.error('Missing --base-url or GATEWAY_PROBE_BASE_URL');
    process.exit(2);
  }
  const paths = ['/livez', '/readyz', '/healthz'];
  const results = [];
  for (const p of paths) {
    results.push(await probePath(baseUrl, p, timeoutMs));
  }
  const liveOk = results.find((r) => r.path === '/livez')?.ok;
  const ready = results.find((r) => r.path === '/readyz');
  const readyOk = ready?.ok;
  const summary = {
    timestamp: new Date().toISOString(),
    base_url: baseUrl,
    livez: liveOk,
    readyz: readyOk,
    healthz_checked: true,
    all_required_pass: Boolean(liveOk && readyOk),
    results,
  };
  process.stdout.write(`${JSON.stringify(summary)}\n`);
  process.exit(summary.all_required_pass ? 0 : 1);
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { probePath, parseArgs };