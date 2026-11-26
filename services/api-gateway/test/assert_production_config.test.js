'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertProductionGatewayConfig,
  DEFAULT_ANON_KEY,
  DEFAULT_POSTGREST_JWT_SECRET,
} = require('../src/assert_production_config');

describe('assertProductionGatewayConfig', () => {
  it('allows non-production with defaults', () => {
    assert.doesNotThrow(() =>
      assertProductionGatewayConfig(
        { postgrestJwtSecret: DEFAULT_POSTGREST_JWT_SECRET, anonKey: DEFAULT_ANON_KEY },
        { APP_ENV: 'staging' },
      ),
    );
  });

  it('blocks production with default JWT secret', () => {
    assert.throws(
      () =>
        assertProductionGatewayConfig(
          {
            postgrestJwtSecret: DEFAULT_POSTGREST_JWT_SECRET,
            anonKey: 'custom-anon-key-value',
            serviceRoleKey: 'a'.repeat(32),
          },
          { APP_ENV: 'production' },
        ),
      /PGRST_JWT_SECRET/,
    );
  });

  it('blocks production with default anon key', () => {
    assert.throws(
      () =>
        assertProductionGatewayConfig(
          {
            postgrestJwtSecret: 'b'.repeat(32),
            anonKey: DEFAULT_ANON_KEY,
            serviceRoleKey: 'c'.repeat(32),
          },
          { NODE_ENV: 'production' },
        ),
      /ANON_KEY/,
    );
  });

  it('passes production with explicit secrets', () => {
    assert.doesNotThrow(() =>
      assertProductionGatewayConfig(
        {
          postgrestJwtSecret: 'd'.repeat(32),
          anonKey: 'public-anon-key-not-default',
          serviceRoleKey: 'e'.repeat(32),
        },
        { APP_ENV: 'production' },
      ),
    );
  });
});