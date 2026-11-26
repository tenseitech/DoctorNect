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

/**
 * Bucket for one caller. In production the five demo accounts (staging Supabase plane) keep
 * their files in the STAGING bucket (S3_BUCKET_STAGING, under demo/), never in the production
 * bucket; every other uid uses the production bucket (under prod/). The plane comes only from
 * the verified Firebase uid (fixed allowlist), never from client input. Outside production
 * there is one bucket (the staging one).
 * @param {string|null|undefined} uid verified caller uid (request.auth.uid)
 */
function resolveS3BucketForUid(uid, env = process.env) {
  const appEnv = String(env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') return resolveS3Bucket(env);
  const { resolveRequestPlane } = require('../db/request_plane');
  if (resolveRequestPlane(uid || null, { appEnv, env }) !== 'supabase') return resolveS3Bucket(env);
  const staging = String(env.S3_BUCKET_STAGING || '').trim();
  if (!staging) {
    const err = new Error('[S3] Demo accounts need S3_BUCKET_STAGING in production (their files never go to the production bucket).');
    err.code = 'failed-precondition';
    throw err;
  }
  return staging;
}

module.exports = {
  getS3BucketName,
  resolveS3Bucket,
  resolveS3BucketForUid,
  resetS3BucketCacheForTesting,
};
