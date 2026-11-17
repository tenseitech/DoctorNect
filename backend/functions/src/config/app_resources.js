'use strict';

function resolveAppEnv(env = process.env) {
  return String(env.APP_ENV || 'staging').trim().toLowerCase();
}

function pickEnvSpecific(env, stagingKey, productionKey, legacyKey) {
  const appEnv = resolveAppEnv(env);
  const staging = String(env[stagingKey] || '').trim();
  const production = String(env[productionKey] || '').trim();
  const legacy = legacyKey ? String(env[legacyKey] || '').trim() : '';

  if (appEnv === 'production') {
    const value = production || legacy;
    if (!value) {
      const err = new Error(`Missing required config for APP_ENV=production: ${productionKey}${legacyKey ? ` or ${legacyKey}` : ''}`);
      err.code = 'failed-precondition';
      throw err;
    }
    if (staging && value === staging) {
      const err = new Error(
        `[AppEnv] Production must not use staging ${stagingKey.replace('STAGING_', '').toLowerCase()} (${stagingKey}=${staging}).`,
      );
      err.code = 'failed-precondition';
      throw err;
    }
    return value;
  }

  const value = staging || legacy;
  if (!value) {
    const err = new Error(`Missing required config for APP_ENV=staging: ${stagingKey}${legacyKey ? ` or ${legacyKey}` : ''}`);
    err.code = 'failed-precondition';
    throw err;
  }
  if (production && value === production) {
    const err = new Error(
      `[AppEnv] Staging must not use production ${productionKey.replace('PRODUCTION_', '').toLowerCase()} (${productionKey}=${production}).`,
    );
    err.code = 'failed-precondition';
    throw err;
  }
  return value;
}

function getS3BucketName(env = process.env) {
  return pickEnvSpecific(
    env,
    'S3_BUCKET_STAGING',
    'S3_BUCKET_PRODUCTION',
    'S3_BUCKET',
  );
}

function getRedisHost(env = process.env) {
  return pickEnvSpecific(
    env,
    'REDIS_HOST_STAGING',
    'REDIS_HOST_PRODUCTION',
    'REDIS_HOST',
  );
}

function assertStagingProductionResourceIsolation(env = process.env) {
  if (String(env.SKIP_APP_ENV_DB_ASSERT || '').trim().toLowerCase() === 'true') {
    return;
  }
  const appEnv = resolveAppEnv(env);
  if (appEnv === 'test') return;

  // Fail-fast when both buckets/hosts are set but APP_ENV points at the wrong one.
  getS3BucketName(env);
  getRedisHost(env);
}

module.exports = {
  resolveAppEnv,
  getS3BucketName,
  getRedisHost,
  assertStagingProductionResourceIsolation,
  pickEnvSpecific,
};
