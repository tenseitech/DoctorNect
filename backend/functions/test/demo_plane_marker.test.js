'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildDemoPlaneClaims, evaluateDemoPlaneMarker, MARKER_TTL_SECONDS,
} = require('../lib/demo_plane_marker');
const { runWithAuth } = require('../src/auth_context');
const { resolveRequestPlane, requestObjectStoragePrefix } = require('../src/db/request_plane');
const { resolveS3BucketForUid, resetS3BucketCacheForTesting } = require('../src/config/s3_bucket');
const { ambulanceLoginClaims } = require('../registration_otp');

const NOW = 1_800_000_000;
const ANON = 'anon_driver_uid_123';
const anonToken = (uid, extra = {}) => ({ uid, sub: uid, firebase: { sign_in_provider: 'anonymous' }, ...extra });
const PROD = { appEnv: 'production', env: { APP_ENV: 'production' }, now: NOW };

test('marker: valid only when anonymous, own uid, not expired, sane TTL, exact value', () => {
  const good = anonToken(ANON, buildDemoPlaneClaims(ANON, NOW));
  assert.equal(evaluateDemoPlaneMarker(good, NOW), 'valid');
  assert.equal(evaluateDemoPlaneMarker(anonToken(ANON), NOW), 'none');
  assert.equal(evaluateDemoPlaneMarker(good, NOW + MARKER_TTL_SECONDS + 1), 'invalid', 'expired');
  assert.equal(evaluateDemoPlaneMarker(anonToken('other_uid', buildDemoPlaneClaims(ANON, NOW)), NOW), 'invalid', 'replayed onto another uid');
  assert.equal(evaluateDemoPlaneMarker({ ...good, firebase: { sign_in_provider: 'custom' } }, NOW), 'invalid', 'non-anonymous');
  assert.equal(evaluateDemoPlaneMarker({ ...good, dn_plane_exp: NOW + 10 * MARKER_TTL_SECONDS }, NOW), 'invalid', 'TTL too long');
  assert.equal(evaluateDemoPlaneMarker({ ...good, dn_plane: 'staging' }, NOW), 'invalid', 'wrong value');
  assert.equal(evaluateDemoPlaneMarker({ ...good, dn_plane_exp: String(NOW + 60) }, NOW), 'invalid', 'string exp');
});

test('demo ambulance (valid marker) routes to staging plane, demo/ prefix, staging bucket', () => {
  resetS3BucketCacheForTesting();
  const token = anonToken(ANON, buildDemoPlaneClaims(ANON, NOW));
  runWithAuth({ uid: ANON, token }, () => {
    assert.equal(resolveRequestPlane(ANON, PROD), 'supabase');
    assert.equal(requestObjectStoragePrefix(ANON, PROD), 'demo/');
  });
  const realNow = Math.floor(Date.now() / 1000);
  runWithAuth({ uid: ANON, token: anonToken(ANON, buildDemoPlaneClaims(ANON, realNow)) }, () => {
    assert.equal(resolveS3BucketForUid(ANON, { APP_ENV: 'production', S3_BUCKET_STAGING: 'stg', S3_BUCKET_PRODUCTION: 'prd' }), 'stg');
  });
  resetS3BucketCacheForTesting();
});

test('real ambulance (no marker) stays on RDS, prod/ prefix, production bucket', () => {
  resetS3BucketCacheForTesting();
  runWithAuth({ uid: 'real_anon_uid', token: anonToken('real_anon_uid') }, () => {
    assert.equal(resolveRequestPlane('real_anon_uid', PROD), 'rds');
    assert.equal(requestObjectStoragePrefix('real_anon_uid', PROD), 'prod/');
    assert.equal(resolveS3BucketForUid('real_anon_uid', { APP_ENV: 'production', S3_BUCKET_STAGING: 'stg', S3_BUCKET_PRODUCTION: 'prd' }), 'prd');
  });
  resetS3BucketCacheForTesting();
});

test('a client cannot self-assign the marker: request data and other uids are ignored', () => {
  // The only input is the verified token in the auth context; request.data is never read.
  runWithAuth({ uid: ANON, token: anonToken(ANON) }, () => {
    assert.equal(resolveRequestPlane(ANON, PROD), 'rds');
  });
  // A valid marker for uid A does not move another uid B.
  runWithAuth({ uid: ANON, token: anonToken(ANON, buildDemoPlaneClaims(ANON, NOW)) }, () => {
    assert.equal(resolveRequestPlane('someone_else', PROD), 'rds');
  });
  // No auth context (e.g. scheduled job): plain allowlist routing.
  assert.equal(resolveRequestPlane(ANON, PROD), 'rds');
});

test('an expired or replayed marker is rejected, never routed to RDS', () => {
  const expired = anonToken(ANON, buildDemoPlaneClaims(ANON, NOW - MARKER_TTL_SECONDS - 10));
  runWithAuth({ uid: ANON, token: expired }, () => {
    assert.throws(() => resolveRequestPlane(ANON, PROD), (e) => e.code === 'unauthenticated');
  });
  const replayed = anonToken(ANON, buildDemoPlaneClaims('another_anon_uid', NOW));
  runWithAuth({ uid: ANON, token: replayed }, () => {
    assert.throws(() => resolveRequestPlane(ANON, PROD), (e) => e.code === 'unauthenticated');
  });
});

test('fixed demo uids still route to staging without a marker; staging env unchanged', () => {
  assert.equal(resolveRequestPlane('rev_fb_amb_001', PROD), 'supabase');
  runWithAuth({ uid: ANON, token: anonToken(ANON, buildDemoPlaneClaims(ANON, NOW)) }, () => {
    assert.equal(resolveRequestPlane(ANON, { appEnv: 'staging', env: { APP_ENV: 'staging' }, now: NOW }), 'staging');
  });
});

test('login claims: marker only for the demo ambulance number on an anonymous session', () => {
  const anonAuth = { uid: ANON, token: anonToken(ANON) };
  const demo = ambulanceLoginClaims({ mobileDigits: '9999900005', auth: anonAuth, now: NOW });
  assert.equal(demo.markDemoPlane, true);
  assert.equal(evaluateDemoPlaneMarker({ ...anonAuth.token, ...demo.claims }, NOW), 'valid');
  // Real ambulance number: plain role claims (also clears a stale marker).
  const real = ambulanceLoginClaims({ mobileDigits: '9876543210', auth: anonAuth, now: NOW });
  assert.equal(real.markDemoPlane, false);
  assert.equal(Object.keys(real.claims).some((k) => k.startsWith('dn_plane')), false);
  // Demo number of another role (doctor 9999900001) or a non-anonymous session: no marker.
  assert.equal(ambulanceLoginClaims({ mobileDigits: '9999900001', auth: anonAuth, now: NOW }).markDemoPlane, false);
  const customAuth = { uid: ANON, token: { uid: ANON, firebase: { sign_in_provider: 'custom' } } };
  assert.equal(ambulanceLoginClaims({ mobileDigits: '9999900005', auth: customAuth, now: NOW }).markDemoPlane, false);
});

test('onCall wrapper runs handlers inside the verified-auth context', async () => {
  const { onCall } = require('../callable_with_auth_context');
  const { currentAuth } = require('../src/auth_context');
  const fn = onCall({ region: 'asia-south1' }, () => currentAuth());
  const seen = await fn.run({ auth: { uid: ANON, token: anonToken(ANON) }, data: { dn_plane: 'demo' } });
  assert.equal(seen.uid, ANON);
  assert.equal(seen.token.dn_plane, undefined, 'request data never becomes a claim');
  const anon = await fn.run({ data: {} });
  assert.equal(anon, null);
});
