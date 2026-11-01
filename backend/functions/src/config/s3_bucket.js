'use strict';

/**
 * Canonical private vault bucket name for Cloud Functions (presign, delete, audit fields).
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {string}
 */
function getS3BucketName(env = process.env) {
  const primary = String(env.S3_BUCKET || '').trim();
  if (primary) return primary;

  const err = new Error(
    'Missing required config: S3_BUCKET (set in functions .env locally or Cloud Functions environment on deploy)',
  );
  err.code = 'failed-precondition';
  throw err;
}

/** Lazy resolver for modules that load before test env is applied. */
let _cached;
function resolveS3Bucket(env = process.env) {
  if (!_cached) _cached = getS3BucketName(env);
  return _cached;
}

function resetS3BucketCacheForTesting() {
  _cached = undefined;
}

module.exports = {
  getS3BucketName,
  resolveS3Bucket,
  resetS3BucketCacheForTesting,
};
