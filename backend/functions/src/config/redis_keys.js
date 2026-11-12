'use strict';

/**
 * Namespaces Redis keys by APP_ENV so staging and production never collide.
 */

function appEnvSlug() {
  const env = String(process.env.APP_ENV || 'staging').trim().toLowerCase();
  if (env === 'production' || env === 'prod') return 'prod';
  if (env === 'staging' || env === 'stage') return 'staging';
  return env.replace(/[^a-z0-9_-]/g, '_') || 'staging';
}

function redisKey(suffix) {
  const tail = String(suffix || '').replace(/^:+/, '');
  return `${appEnvSlug()}:${tail}`;
}

module.exports = {
  appEnvSlug,
  redisKey,
};
