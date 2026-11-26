'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  getS3BucketName,
  getRedisHost,
} = require('../src/config/app_resources');
const { resetS3BucketCacheForTesting } = require('../src/config/s3_bucket');

describe('app_resources env isolation', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
    resetS3BucketCacheForTesting();
  });

  afterEach(() => {
    process.env = original;
    resetS3BucketCacheForTesting();
  });

  it('staging cannot use production S3 bucket', () => {
    process.env.APP_ENV = 'staging';
    process.env.S3_BUCKET_STAGING = 'staging-vault';
    process.env.S3_BUCKET_PRODUCTION = 'prod-vault';
    assert.equal(getS3BucketName(), 'staging-vault');
    process.env.S3_BUCKET_STAGING = 'prod-vault';
    assert.throws(() => getS3BucketName(), /Staging must not use the production S3 bucket: S3_BUCKET_STAGING/);
  });

  it('production cannot use staging S3 bucket', () => {
    process.env.APP_ENV = 'production';
    process.env.S3_BUCKET_STAGING = 'staging-vault';
    process.env.S3_BUCKET_PRODUCTION = 'prod-vault';
    assert.equal(getS3BucketName(), 'prod-vault');
    process.env.S3_BUCKET_PRODUCTION = 'staging-vault';
    assert.throws(() => getS3BucketName(), /Production must not use the staging S3 bucket: S3_BUCKET_PRODUCTION .*set S3_BUCKET_PRODUCTION/);
    // Legacy S3_BUCKET equal to staging names the real cause (S3_BUCKET_PRODUCTION missing).
    delete process.env.S3_BUCKET_PRODUCTION;
    process.env.S3_BUCKET = 'staging-vault';
    assert.throws(() => getS3BucketName(), /S3_BUCKET \(S3_BUCKET_PRODUCTION is not set\)/);
  });

  it('redis host follows APP_ENV', () => {
    process.env.APP_ENV = 'staging';
    process.env.REDIS_HOST_STAGING = 'redis-staging.local';
    process.env.REDIS_HOST_PRODUCTION = 'redis-prod.local';
    assert.equal(getRedisHost(), 'redis-staging.local');
    process.env.APP_ENV = 'production';
    assert.equal(getRedisHost(), 'redis-prod.local');
  });
});
