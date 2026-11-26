'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const {
  assertHermeticAppEnv,
  assertNoLiveDeployTargets,
  HARNESS_FLAG,
} = require(path.resolve(__dirname, '../../../scripts/lib/test_harness_env'));

test('harness: APP_ENV is always test for default npm test', () => {
  assert.strictEqual(process.env[HARNESS_FLAG], '1');
  assert.strictEqual(process.env.APP_ENV, 'test');
  assertHermeticAppEnv();
});

test('harness: polluted shell deploy keys are not visible in test files', () => {
  assert.doesNotThrow(() => assertNoLiveDeployTargets());
});