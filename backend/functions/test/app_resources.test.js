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
    assert.throws(() => getS3BucketName(), /Staging must not use production/);
  });

  it('production cannot use staging S3 bucket', () => {
    process.env.APP_ENV = 'production';
    process.env.S3_BUCKET_STAGING = 'staging-vault';
    process.env.S3_BUCKET_PRODUCTION = 'prod-vault';
    assert.equal(getS3BucketName(), 'prod-vault');
    process.env.S3_BUCKET_PRODUCTION = 'staging-vault';
    assert.throws(() => getS3BucketName(), /Production must not use staging/);
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
