'use strict';

/**
 * Scheduled read-only ping against the demo Supabase project (prevents free-tier pause).
 * DEMO_SUPABASE_URL is a plain env value (a URL, not a secret; the OTP functions read it too).
 * Only DEMO_SUPABASE_SERVICE_ROLE_KEY comes from Firebase Secret Manager.
 */

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { demoSupabaseServiceRoleKey } = require('./demo_plane_secrets');

const KEEPALIVE_EVENT_FAIL = 'supabase_keepalive_failed';
const KEEPALIVE_EVENT_OK = 'supabase_keepalive_ok';
const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_MAX_ATTEMPTS = 3;
const BACKOFF_BASE_MS = 1_000;

function normalizeBaseUrl(raw) {
  return String(raw || '').trim().replace(/\/+$/, '');
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * @param {object} options
 * @param {string} options.baseUrl Supabase project URL (https://xxx.supabase.co)
 * @param {string} options.apiKey service role or least-privilege REST key
 * @param {typeof fetch} [options.fetchImpl]
 * @param {number} [options.timeoutMs]
 * @param {number} [options.maxAttempts]
 */
async function runSupabaseKeepalivePing(options = {}) {
  const baseUrl = normalizeBaseUrl(options.baseUrl || process.env.DEMO_SUPABASE_URL);
  const apiKey = String(options.apiKey || process.env.DEMO_SUPABASE_SERVICE_ROLE_KEY || '').trim();
  const fetchImpl = options.fetchImpl || globalThis.fetch;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const maxAttempts = options.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;

  if (!baseUrl || !apiKey) {
    const err = new Error('supabase_keepalive_missing_credentials');
    err.code = KEEPALIVE_EVENT_FAIL;
    throw err;
  }
  if (typeof fetchImpl !== 'function') {
    const err = new Error('fetch_unavailable');
    err.code = KEEPALIVE_EVENT_FAIL;
    throw err;
  }

  const target = `${baseUrl}/rest/v1/system_config?select=key&limit=1`;
  let lastError = null;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const timer = controller
      ? setTimeout(() => controller.abort(), timeoutMs)
      : null;
    try {
      const res = await fetchImpl(target, {
        method: 'GET',
        headers: {
          apikey: apiKey,
          Authorization: `Bearer ${apiKey}`,
          Accept: 'application/json',
        },
        signal: controller?.signal,
      });
      if (timer) clearTimeout(timer);
      if (!res.ok) {
        const body = await res.text().catch(() => '');
        const err = new Error(`http_${res.status}`);
        err.status = res.status;
        err.bodySnippet = body.slice(0, 120);
        throw err;
      }
      await res.json().catch(() => ({}));
      return { ok: true, attempt, targetHost: new URL(baseUrl).host };
    } catch (err) {
      if (timer) clearTimeout(timer);
      lastError = err;
      if (attempt < maxAttempts) {
        await sleep(BACKOFF_BASE_MS * 2 ** (attempt - 1));
      }
    }
  }

  const wrapped = new Error(KEEPALIVE_EVENT_FAIL);
  wrapped.code = KEEPALIVE_EVENT_FAIL;
  wrapped.cause = lastError;
  wrapped.attempts = maxAttempts;
  throw wrapped;
}

async function supabaseKeepaliveHandler() {
  try {
    const result = await runSupabaseKeepalivePing({
      baseUrl: process.env.DEMO_SUPABASE_URL,
      apiKey: process.env.DEMO_SUPABASE_SERVICE_ROLE_KEY,
    });
    console.log(
      JSON.stringify({
        severity: 'INFO',
        event: KEEPALIVE_EVENT_OK,
        attempt: result.attempt,
        host: result.targetHost,
      }),
    );
  } catch (err) {
    console.error(
      JSON.stringify({
        severity: 'ERROR',
        event: KEEPALIVE_EVENT_FAIL,
        message: err.code === KEEPALIVE_EVENT_FAIL ? KEEPALIVE_EVENT_FAIL : String(err.message || err),
        attempts: err.attempts || DEFAULT_MAX_ATTEMPTS,
      }),
    );
    throw err;
  }
}

const supabaseKeepalive = onSchedule(
  {
    schedule: '30 3 * * *',
    timeZone: 'Asia/Kolkata',
    region: 'asia-south1',
    timeoutSeconds: 30,
    secrets: [demoSupabaseServiceRoleKey],
  },
  supabaseKeepaliveHandler,
);

module.exports = {
  supabaseKeepalive,
  supabaseKeepaliveHandler,
  runSupabaseKeepalivePing,
  demoSupabaseServiceRoleKey,
  KEEPALIVE_EVENT_FAIL,
  KEEPALIVE_EVENT_OK,
};