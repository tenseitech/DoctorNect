'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  verifyProductionConfig,
  isSupabaseCloudUrl,
} = require('../../scripts/verify_production_build_config');

test('verify_production_build_config: production API base rules (CFG-01)', async (t) => {
  const stagingRef = 'staging-project-ref';
  const dummyAnon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy_valid_length_key_for_testing_purposes_only_1234567890';
  const gatewayUrl = 'https://api.gateway.doctornect.example';

  await t.test('fails when SUPABASE_URL is any *.supabase.co (including real staging ref)', () => {
    const result = verifyProductionConfig({
      clientOnly: true,
      allowStaging: false,
      STAGING_SUPABASE_URL: `https://${stagingRef}.supabase.co`,
      SUPABASE_URL: `https://${stagingRef}.supabase.co`,
      PROD_GATEWAY_URL: gatewayUrl,
      SUPABASE_ANON_KEY: dummyAnon,
    });

    assert.equal(result.success, false);
    assert.ok(
      result.errors.some((e) => e.includes('Supabase Cloud Blocked') || e.includes('.supabase.co')),
      `expected Supabase cloud block, got: ${result.errors.join('; ')}`,
    );
  });

  await t.test('fails for any other *.supabase.co ref via production cloud rule', () => {
    const result = verifyProductionConfig({
      clientOnly: true,
      allowStaging: false,
      STAGING_SUPABASE_URL: `https://${stagingRef}.supabase.co`,
      SUPABASE_URL: 'https://legacy-staging-ref.supabase.co',
      PROD_GATEWAY_URL: gatewayUrl,
      SUPABASE_ANON_KEY: dummyAnon,
    });

    assert.equal(result.success, false);
    assert.ok(isSupabaseCloudUrl('https://legacy-staging-ref.supabase.co'));
  });

  await t.test('passes when SUPABASE_URL is Auth Gateway (not Supabase cloud)', () => {
    const result = verifyProductionConfig({
      clientOnly: true,
      allowStaging: false,
      STAGING_SUPABASE_URL: `https://${stagingRef}.supabase.co`,
      PROD_GATEWAY_URL: gatewayUrl,
      SUPABASE_URL: gatewayUrl,
      SUPABASE_ANON_KEY: dummyAnon,
    });

    assert.equal(result.success, true, result.errors.join('; '));
    assert.equal(result.errors.length, 0);
  });

  await t.test('allows staging Supabase URL when allowStaging is true', () => {
    const result = verifyProductionConfig({
      clientOnly: true,
      allowStaging: true,
      STAGING_SUPABASE_URL: `https://${stagingRef}.supabase.co`,
      SUPABASE_URL: `https://${stagingRef}.supabase.co`,
      SUPABASE_ANON_KEY: dummyAnon,
    });

    assert.equal(result.success, true, result.errors.join('; '));
    assert.ok(
      result.warnings.some((w) => w.includes('allow-staging') || w.includes('Staging')),
      'expected staging warning when allowStaging',
    );
  });
});
