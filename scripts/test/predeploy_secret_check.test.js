'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { validateSupabaseDeployEnv } = require('../predeploy_secret_check');

test('predeploy: production rejects *.supabase.co SUPABASE_URL', () => {
  const { errors } = validateSupabaseDeployEnv({
    APP_ENV: 'production',
    STAGING_SUPABASE_URL: 'https://staging-project-ref.supabase.co',
    SUPABASE_URL: 'https://staging-project-ref.supabase.co',
    PROD_GATEWAY_URL: 'https://api.gateway.example',
  });
  assert.ok(errors.some((e) => e.includes('*.supabase.co')));
});

test('predeploy: production accepts Auth Gateway URL', () => {
  const { errors, warnings } = validateSupabaseDeployEnv({
    APP_ENV: 'production',
    STAGING_SUPABASE_URL: 'https://staging-project-ref.supabase.co',
    SUPABASE_URL: 'https://api.gateway.example',
    PROD_GATEWAY_URL: 'https://api.gateway.example',
  });
  assert.equal(errors.length, 0, errors.join('; '));
  assert.equal(warnings.length, 0);
});

test('predeploy: staging anchor ref derived from STAGING_SUPABASE_URL only', () => {
  const { resolveStagingProjectRefFromEnv } = require('../lib/infra_url_policy');
  const ref = resolveStagingProjectRefFromEnv({
    STAGING_SUPABASE_URL: 'https://staging-project-ref.supabase.co',
  });
  assert.equal(ref, 'staging-project-ref');
});
