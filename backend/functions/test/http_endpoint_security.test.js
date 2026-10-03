'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { HttpsError } = require('firebase-functions/v2/https');
const {
  DEFAULT_AMBULANCE_HTTP_ORIGINS,
  parseCommaSeparatedOrigins,
  resolveAmbulanceHttpAllowedOrigins,
  isAmbulanceHttpOriginAllowed,
  handleAmbulanceHttpPreflight,
  readAppCheckToken,
  isAmbulanceHttpAppCheckEnforced,
  assertAmbulanceHttpAppCheck,
} = require('../http_endpoint_security');

function createMockResponse() {
  const headers = {};
  return {
    headers,
    statusCode: 200,
    body: null,
    set(name, value) {
      headers[name.toLowerCase()] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    send(payload) {
      this.body = payload;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

test('resolveAmbulanceHttpAllowedOrigins merges defaults with env extras', () => {
  const origins = resolveAmbulanceHttpAllowedOrigins({
    AMBULANCE_HTTP_ALLOWED_ORIGINS: 'http://localhost:5000, https://doctornect.com',
  });
  assert.deepEqual(origins.slice(0, 2), DEFAULT_AMBULANCE_HTTP_ORIGINS);
  assert.equal(origins.includes('http://localhost:5000'), true);
  assert.equal(origins.includes('https://doctornect.com'), true);
});

test('parseCommaSeparatedOrigins trims and drops empty entries', () => {
  assert.deepEqual(
    parseCommaSeparatedOrigins(' https://a.test , ,https://b.test '),
    ['https://a.test', 'https://b.test'],
  );
});

test('isAmbulanceHttpOriginAllowed rejects unknown browser origins', () => {
  const allowed = resolveAmbulanceHttpAllowedOrigins({});
  assert.equal(isAmbulanceHttpOriginAllowed('https://evil.example', allowed), false);
  assert.equal(isAmbulanceHttpOriginAllowed(DEFAULT_AMBULANCE_HTTP_ORIGINS[0], allowed), true);
  assert.equal(isAmbulanceHttpOriginAllowed(undefined, allowed), true);
});

test('handleAmbulanceHttpPreflight answers OPTIONS for allowed origins', () => {
  const allowed = resolveAmbulanceHttpAllowedOrigins({});
  const req = {
    method: 'OPTIONS',
    headers: { origin: DEFAULT_AMBULANCE_HTTP_ORIGINS[0] },
  };
  const res = createMockResponse();

  const handled = handleAmbulanceHttpPreflight(req, res, allowed);
  assert.equal(handled, true);
  assert.equal(res.statusCode, 204);
  assert.equal(
    res.headers['access-control-allow-origin'],
    DEFAULT_AMBULANCE_HTTP_ORIGINS[0],
  );
  assert.match(res.headers['access-control-allow-headers'], /X-Firebase-AppCheck/i);
});

test('handleAmbulanceHttpPreflight blocks OPTIONS from disallowed origins', () => {
  const allowed = resolveAmbulanceHttpAllowedOrigins({});
  const req = {
    method: 'OPTIONS',
    headers: { origin: 'https://attacker.example' },
  };
  const res = createMockResponse();

  const handled = handleAmbulanceHttpPreflight(req, res, allowed);
  assert.equal(handled, true);
  assert.equal(res.statusCode, 403);
});

test('readAppCheckToken reads X-Firebase-AppCheck header', () => {
  const token = readAppCheckToken({
    headers: { 'x-firebase-appcheck': 'abc123' },
  });
  assert.equal(token, 'abc123');
});

test('isAmbulanceHttpAppCheckEnforced defaults to false', () => {
  assert.equal(isAmbulanceHttpAppCheckEnforced({}), false);
  assert.equal(isAmbulanceHttpAppCheckEnforced({ ENFORCE_AMBULANCE_HTTP_APP_CHECK: 'true' }), true);
});

test('assertAmbulanceHttpAppCheck skips verification when enforcement is off', async () => {
  await assertAmbulanceHttpAppCheck({ headers: {} }, { enforce: false });
});

test('assertAmbulanceHttpAppCheck rejects missing token when enforcement is on', async () => {
  await assert.rejects(
    () => assertAmbulanceHttpAppCheck({ headers: {} }, { enforce: true }),
    (err) => err instanceof HttpsError && err.code === 'failed-precondition',
  );
});

test('assertAmbulanceHttpAppCheck verifies token when enforcement is on', async () => {
  let verified = null;
  await assertAmbulanceHttpAppCheck(
    { headers: { 'x-firebase-appcheck': 'good-token' } },
    {
      enforce: true,
      verifyToken: async (token) => {
        verified = token;
      },
    },
  );
  assert.equal(verified, 'good-token');
});
