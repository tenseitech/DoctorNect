'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { ALLOWLIST_TABLES, SYSTEM_CONFIG_PUBLIC_KEYS } = require('./anon_surface_audit');

describe('anon_surface_audit constants', () => {
  it('allowlist matches staging security policy', () => {
    assert.deepEqual([...ALLOWLIST_TABLES].sort(), [
      'doctor_directory',
      'lab_catalog_tests',
      'review_public',
      'system_config',
    ]);
  });

  it('system_config exposes only two public keys', () => {
    assert.deepEqual(SYSTEM_CONFIG_PUBLIC_KEYS, ['patient_module_status', 'promoted_ads']);
  });
});
