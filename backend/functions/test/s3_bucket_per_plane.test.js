'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { resolveS3BucketForUid, resetS3BucketCacheForTesting } = require('../src/config/s3_bucket');

const PROD = { APP_ENV: 'production', S3_BUCKET_STAGING: 'stage-bkt', S3_BUCKET_PRODUCTION: 'prod-bkt' };

test('production: demo accounts use the staging bucket, real users the production bucket', () => {
  resetS3BucketCacheForTesting();
  for (const uid of ['rev_fb_doc_001', 'rev_fb_pat_001', 'rev_fb_store_001', 'rev_fb_lab_001', 'rev_fb_amb_001']) {
    assert.equal(resolveS3BucketForUid(uid, PROD), 'stage-bkt', uid);
  }
  assert.equal(resolveS3BucketForUid('real_user_uid', PROD), 'prod-bkt');
  assert.equal(resolveS3BucketForUid(null, PROD), 'prod-bkt', 'unknown caller fails closed to the production plane');
  resetS3BucketCacheForTesting();
});

test('production: demo routing switch cannot move a real user to the staging bucket', () => {
  resetS3BucketCacheForTesting();
  assert.equal(resolveS3BucketForUid('real_user_uid', { ...PROD, DEMO_REAL_ROUTING_ENABLED: '1' }), 'prod-bkt');
  resetS3BucketCacheForTesting();
});

test('production demo account without S3_BUCKET_STAGING is refused (never falls back to prod bucket)', () => {
  resetS3BucketCacheForTesting();
  assert.throws(() => resolveS3BucketForUid('rev_fb_doc_001', { APP_ENV: 'production', S3_BUCKET_PRODUCTION: 'prod-bkt' }), /S3_BUCKET_STAGING/);
  resetS3BucketCacheForTesting();
});

test('every S3 call site passes the verified caller uid (no plane-less bucket lookups)', () => {
  for (const f of ['s3_storage.js', 'delete_my_account.js']) {
    const src = fs.readFileSync(path.join(__dirname, '..', f), 'utf8');
    assert.equal(/s3Bucket\(\)/.test(src), false, `${f} has s3Bucket() without a uid`);
    assert.doesNotMatch(src, /resolveS3Bucket\(\)/);
  }
});
