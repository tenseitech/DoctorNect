'use strict';

/**
 * Boot-time flag only — kept separate from pg_pool.js so index.js graph does not load pg driver config.
 */
function isProductionBootRequiresDatabaseUrl() {
  return false;
}

module.exports = {
  isProductionBootRequiresDatabaseUrl,
};