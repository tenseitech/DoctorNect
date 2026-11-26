'use strict';

/**
 * Production S3 data-plane isolation: demo accounts write under demo/, real users under prod/,
 * legacy unprefixed keys belong to prod/, and no caller can touch the other plane's objects.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const { _test: s3 } = require('../s3_storage');
const { createPgFromLegacySeed } = require('./helpers/legacy_seed_to_pg');

const DEMO_UID = 'rev_fb_pat_001';
const REAL_UID = 'real_patient_uid';

let saved;
test.beforeEach(() => {
  saved = {
    appEnv: process.env.APP_ENV, routing: process.env.DEMO_REAL_ROUTING_ENABLED, allow: process.env.DEMO_FIREBASE_UID_ALLOWLIST,
    stg: process.env.S3_BUCKET_STAGING, prd: process.env.S3_BUCKET_PRODUCTION, b: process.env.S3_BUCKET,
  };
  process.env.APP_ENV = 'production';
  process.env.S3_BUCKET_STAGING = 'unit-test-stage-bucket';
  delete process.env.S3_BUCKET;
  process.env.S3_BUCKET_PRODUCTION = 'unit-test-prod-bucket';
  require('../src/config/s3_bucket').resetS3BucketCacheForTesting();
  process.env.DEMO_REAL_ROUTING_ENABLED = '1';
  process.env.DEMO_FIREBASE_UID_ALLOWLIST = DEMO_UID;
  const { S3Client } = require('@aws-sdk/client-s3');
  const client = new S3Client({ region: 'ap-south-1', credentials: { accessKeyId: 'mock', secretAccessKey: 'mock' } });
  client.send = async () => ({});
  s3.setS3ClientForTesting(client);
});
test.afterEach(() => {
  for (const [k, v] of Object.entries({
    APP_ENV: saved.appEnv, DEMO_REAL_ROUTING_ENABLED: saved.routing, DEMO_FIREBASE_UID_ALLOWLIST: saved.allow,
    S3_BUCKET_STAGING: saved.stg, S3_BUCKET_PRODUCTION: saved.prd, S3_BUCKET: saved.b,
  })) {
    if (v === undefined) delete process.env[k]; else process.env[k] = v;
  }
  require('../src/config/s3_bucket').resetS3BucketCacheForTesting();
});

test('plane prefix follows the server-side data plane', () => {
  assert.equal(s3.planePrefixFor(DEMO_UID), 'demo/');
  assert.equal(s3.planePrefixFor(REAL_UID), 'prod/');
  process.env.APP_ENV = 'staging';
  assert.equal(s3.planePrefixFor(DEMO_UID), '', 'staging bucket is separate; no prefix');
});

test('toLogicalKey strips own plane, treats unprefixed as prod, rejects the other plane', () => {
  assert.equal(s3.toLogicalKey('prod/health_records/p1/r1/a.pdf', REAL_UID), 'health_records/p1/r1/a.pdf');
  assert.equal(s3.toLogicalKey('health_records/p1/r1/a.pdf', REAL_UID), 'health_records/p1/r1/a.pdf');
  assert.equal(s3.toLogicalKey('demo/health_records/p1/r1/a.pdf', DEMO_UID), 'health_records/p1/r1/a.pdf');
  assert.throws(() => s3.toLogicalKey('prod/health_records/p1/r1/a.pdf', DEMO_UID), (e) => e.code === 'permission-denied');
  assert.throws(() => s3.toLogicalKey('health_records/p1/r1/a.pdf', DEMO_UID), (e) => e.code === 'permission-denied');
  assert.throws(() => s3.toLogicalKey('demo/health_records/p1/r1/a.pdf', REAL_UID), (e) => e.code === 'permission-denied');
});

test('uploads are written under the caller plane prefix', async () => {
  const db = createPgFromLegacySeed({ users: { [REAL_UID]: { role: 'patient', profileId: 'p1' }, [DEMO_UID]: { role: 'patient', profileId: 'p1' } } });
  const req = { purpose: 'patient_profile', parentId: 'p1', fileName: 'a.jpg', contentType: 'image/jpeg', sizeBytes: 1000 };
  const real = await s3.getS3UploadUrlHandler(req, { uid: REAL_UID }, db);
  const demo = await s3.getS3UploadUrlHandler(req, { uid: DEMO_UID }, db);
  assert.ok(real.objectKey.startsWith('prod/patients/p1/profile/'));
  assert.ok(demo.objectKey.startsWith('demo/patients/p1/profile/'));
  // Demo files go to the staging bucket, real users' files to the production bucket.
  const urlOf = (r) => String(r.uploadUrl || r.url || '');
  assert.match(urlOf(real), /unit-test-prod-bucket/);
  assert.doesNotMatch(urlOf(real), /unit-test-stage-bucket/);
  assert.match(urlOf(demo), /unit-test-stage-bucket/);
  assert.doesNotMatch(urlOf(demo), /unit-test-prod-bucket/);
});

test('a demo account with a colliding profile id cannot read a real user record', async () => {
  // Same profile id "p1" exists on both planes; isolation must not rely on ids being unique.
  const db = createPgFromLegacySeed({ users: { [DEMO_UID]: { role: 'patient', profileId: 'p1' } } });
  for (const key of ['prod/health_records/p1/r1/a.pdf', 'health_records/p1/r1/a.pdf']) {
    await assert.rejects(s3.getS3DownloadUrlHandler({ objectKey: key }, { uid: DEMO_UID }, db), (e) => e.code === 'permission-denied');
    await assert.rejects(s3.deleteS3ObjectHandler({ objectKey: key }, { uid: DEMO_UID }, db), (e) => e.code === 'permission-denied');
  }
  const own = await s3.getS3DownloadUrlHandler({ objectKey: 'demo/health_records/p1/r1/a.pdf' }, { uid: DEMO_UID }, db);
  assert.ok(own.url);
});
