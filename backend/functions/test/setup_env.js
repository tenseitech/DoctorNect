'use strict';

/**
 * Default `npm test` harness: isolated from deploy/local `.env` (Firebase deploy loads
 * that file; unit tests must not inherit live Redis, Supabase, S3, or Auth credentials).
 */

const path = require('path');
const {
  activateTestHarness,
} = require(path.resolve(__dirname, '../../../scripts/lib/test_harness_env'));

activateTestHarness();

/** In-memory Redis (TTL-aware) so OTP / rate-limit / session paths run for real without TCP. */
const { createMemoryRedis } = require('./helpers/memory_redis');

try {
  const { setRedisClientForTesting } = require('../redis');
  setRedisClientForTesting(createMemoryRedis());
} catch (_) {
  // redis module optional during early bootstrap
}

/**
 * Default empty in-memory Postgres (PostgREST double) so lookups resolve to "not found"
 * instead of failing closed for lack of a database. Tests that exercise real client routing
 * call setDatabaseClientForTesting(null) first; tests needing rows install their own.
 */
try {
  const { setDatabaseClientForTesting } = require('../src/db/client');
  const { createMemoryPostgrest } = require('./helpers/memory_postgrest');
  setDatabaseClientForTesting(createMemoryPostgrest());
} catch (_) {
  // optional during early bootstrap
}