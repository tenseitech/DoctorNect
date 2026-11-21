'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');
const { findRepoRoot } = require('../lib/repo_root');
const { collectDefineSecretNames } = require('../lib/functions_define_secrets');
const { parseEnvFile } = require('../lib/parse_env_file');

const FUNCTIONS = [
  {
    name: 'sendUserRegistrationOtp',
    service: 'senduserregistrationotp',
    secrets: ['SUPABASE_SERVICE_ROLE_KEY'],
    redisSecretsWhenMirror: true,
  },
  {
    name: 'verifyUserRegistrationOtp',
    service: 'verifyuserregistrationotp',
    secrets: ['SUPABASE_SERVICE_ROLE_KEY'],
    redisSecretsWhenMirror: true,
  },
  {
    name: 'completeMobileOtpLogin',
    service: 'completemobileotplogin',
    secrets: ['SUPABASE_SERVICE_ROLE_KEY'],
    redisSecretsWhenMirror: false,
  },
  {
    name: 'completeAmbulanceMobileOtpLogin',
    service: 'completeambulancemobileotplogin',
    secrets: [],
    redisSecretsWhenMirror: false,
  },
];

const OTP_KEYS = [
  'REDIS_HOST',
  'REDIS_PORT',
  'REDIS_PASSWORD',
  'MSG91_AUTH_KEY',
  'PROXY_SECRET',
  'MSG91_TEMPLATE_ID',
  'MSG91_TEMPLATE_ID_REGISTRATION',
  'MSG91_TEMPLATE_ID_LOGIN',
  'OTP_HMAC_SECRET',
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_SECRET_KEY',
  'REVIEWER_OTP_ENABLED',
  'REVIEW_FIXED_OTP',
  'REVIEW_ACCESS_UNTIL',
];

function envPresence(env, key) {
  const v = env[key];
  return v !== undefined && String(v).trim() !== '';
}

test('per-function OTP env: plain .env vs secret bindings (deployed mirror off)', () => {
  const root = findRepoRoot();
  const generatedPath = path.join(root, 'backend', 'functions', '.env');
  if (!fs.existsSync(generatedPath)) {
    test.skip('backend/functions/.env missing — run materialize first');
    return;
  }
  const generated = parseEnvFile(generatedPath);
  const defineSecrets = collectDefineSecretNames(path.join(root, 'backend', 'functions'));
  const mirrorOn = envPresence(generated, 'OTP_REDIS_MIRROR') && String(generated.OTP_REDIS_MIRROR).toLowerCase() === 'on';

  for (const fn of FUNCTIONS) {
    const bound = [...fn.secrets];
    if (fn.redisSecretsWhenMirror && mirrorOn) {
      bound.push('REDIS_HOST', 'REDIS_PORT', 'REDIS_PASSWORD');
    }
    for (const key of OTP_KEYS) {
      const inGenerated = envPresence(generated, key);
      const isSecretName = defineSecrets.has(key);
      const boundHere = bound.includes(key);
      if (isSecretName && inGenerated) {
        assert.fail(`${fn.name}: generated .env must not contain secret-bound key ${key}`);
      }
      if (boundHere && key.startsWith('REDIS_')) {
        assert.equal(
          inGenerated,
          false,
          `${fn.name}: REDIS_* must come from Secret Manager binding, not plain .env`,
        );
      }
    }
  }

  assert.equal(
    envPresence(generated, 'RATE_LIMIT_BACKEND') ? generated.RATE_LIMIT_BACKEND : '',
    envPresence(generated, 'RATE_LIMIT_BACKEND') ? String(generated.RATE_LIMIT_BACKEND) : 'unset',
  );
});