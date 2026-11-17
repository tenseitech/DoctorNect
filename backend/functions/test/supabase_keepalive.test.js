'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  runSupabaseKeepalivePing,
  KEEPALIVE_EVENT_FAIL,
} = require('../supabase_keepalive');

function mockFetchSequence(responses) {
  let i = 0;
  return async () => {
    const next = responses[i++];
    if (!next) throw new Error('unexpected fetch');
    if (next.throw) throw next.throw;
    return {
      ok: next.ok !== false,
      status: next.status || 200,
      text: async () => next.body || '[]',
      json: async () => next.json ?? [],
    };
  };
}

test('keepalive success on first attempt', async () => {
  const fetchImpl = mockFetchSequence([{ json: [{ key: 'patient_module_status' }] }]);
  const res = await runSupabaseKeepalivePing({
    baseUrl: 'https://example.supabase.co',
    apiKey: 'test-key-minimum-twenty-chars',
    fetchImpl,
    timeoutMs: 5000,
    maxAttempts: 3,
  });
  assert.equal(res.ok, true);
  assert.equal(res.attempt, 1);
});

test('keepalive retries then succeeds', async () => {
  const fetchImpl = mockFetchSequence([
    { throw: new Error('network') },
    { throw: new Error('network') },
    { json: [{ key: 'x' }] },
  ]);
  const res = await runSupabaseKeepalivePing({
    baseUrl: 'https://example.supabase.co',
    apiKey: 'test-key-minimum-twenty-chars',
    fetchImpl,
    maxAttempts: 3,
    timeoutMs: 5000,
  });
  assert.equal(res.attempt, 3);
});

test('keepalive logs fixed failure code after retries', async () => {
  const fetchImpl = mockFetchSequence([
    { ok: false, status: 503, body: 'paused' },
    { ok: false, status: 503, body: 'paused' },
    { ok: false, status: 503, body: 'paused' },
  ]);
  await assert.rejects(
    () =>
      runSupabaseKeepalivePing({
        baseUrl: 'https://example.supabase.co',
        apiKey: 'test-key-minimum-twenty-chars',
        fetchImpl,
        maxAttempts: 3,
        timeoutMs: 5000,
      }),
    (err) => {
      assert.equal(err.message, KEEPALIVE_EVENT_FAIL);
      assert.equal(err.code, KEEPALIVE_EVENT_FAIL);
      return true;
    },
  );
});