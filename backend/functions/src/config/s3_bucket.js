'use strict';

const { getS3BucketName: resolveS3FromEnv } = require('./app_resources');

/**
 * Canonical private vault bucket name for Cloud Functions (presign, delete, audit fields).
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {string}
 */
function getS3BucketName(env = process.env) {
  return resolveS3FromEnv(env);
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
