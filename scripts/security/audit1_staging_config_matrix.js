'use strict';

/**
 * Safe staging readiness matrix (presence only — never prints secret values).
 */
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const repoRoot = path.join(__dirname, '..', '..');
require(path.join(repoRoot, 'scripts', 'lib', 'bootstrap_root_env')).loadRootEnv();

function flag(key) {
  return String(process.env[key] || '').trim() ? 'YES' : 'NO';
}

function fileExistsFromEnv(key) {
  const p = String(process.env[key] || '').trim();
  if (!p) return 'NO';
  const abs = path.isAbsolute(p) ? p : path.join(repoRoot, p);
  return fs.existsSync(abs) ? 'YES' : 'NO';
}

function urlHostOnly(key) {
  const raw = String(process.env[key] || '').trim();
  if (!raw) return '(unset)';
  try {
    return new URL(raw).host;
  } catch (_) {
    return '(invalid-url-shape)';
  }
}

const awsCli = spawnSync('aws', ['--version'], { encoding: 'utf8', shell: true });
const awsCliOk = !awsCli.error && awsCli.status === 0;

const firebaseRc = JSON.parse(fs.readFileSync(path.join(repoRoot, '.firebaserc'), 'utf8'));
const firebaseDefaultProject = firebaseRc.projects?.default || '(unknown)';

const matrix = {
  date: new Date().toISOString().slice(0, 10),
  SEC_04: {
    AUDIT1_STAGING_GATEWAY_URL_set: flag('AUDIT1_STAGING_GATEWAY_URL'),
    AUDIT1_STAGING_GATEWAY_host: urlHostOnly('AUDIT1_STAGING_GATEWAY_URL'),
    AUDIT1_TEST_FIREBASE_EMAIL_set: flag('AUDIT1_TEST_FIREBASE_EMAIL'),
    AUDIT1_TEST_FIREBASE_PASSWORD_set: flag('AUDIT1_TEST_FIREBASE_PASSWORD'),
    GOOGLE_APPLICATION_CREDENTIALS_set: flag('GOOGLE_APPLICATION_CREDENTIALS'),
    GOOGLE_APPLICATION_CREDENTIALS_file_exists: fileExistsFromEnv('GOOGLE_APPLICATION_CREDENTIALS'),
    STAGING_SUPABASE_URL_set: flag('STAGING_SUPABASE_URL'),
    STAGING_SUPABASE_host: urlHostOnly('STAGING_SUPABASE_URL'),
    PROD_GATEWAY_URL_set: flag('PROD_GATEWAY_URL'),
    PROD_GATEWAY_host: urlHostOnly('PROD_GATEWAY_URL'),
    firebase_default_project: firebaseDefaultProject,
    note: 'Use AUDIT1_* and non-production Firebase project only for SEC-04 closure.',
  },
  SEC_07: {
    AUDIT1_STAGING_HOSTING_URL_set: flag('AUDIT1_STAGING_HOSTING_URL'),
    AUDIT1_STAGING_HOSTING_host: urlHostOnly('AUDIT1_STAGING_HOSTING_URL'),
    firebase_hosting_site: (() => {
      try {
        const fj = JSON.parse(fs.readFileSync(path.join(repoRoot, 'firebase.json'), 'utf8'));
        return fj.hosting?.site || '(none)';
      } catch (_) {
        return '(unreadable)';
      }
    })(),
    note: 'Do not use production hosting URL unless explicitly designated staging.',
  },
  SEC_08: {
    AUDIT1_STAGING_GATEWAY_URL_set: flag('AUDIT1_STAGING_GATEWAY_URL'),
    AWS_REGION_set: flag('AWS_REGION'),
    AWS_ACCESS_KEY_ID_set: flag('AWS_ACCESS_KEY_ID'),
    AWS_PROFILE_set: flag('AWS_PROFILE'),
    AWS_CLI_available: awsCliOk ? 'YES' : 'NO',
    wire_gateway_rate_limit_redis_in_tf: fs
      .readFileSync(path.join(repoRoot, 'infra', 'aws', 'ecs.tf'), 'utf8')
      .includes('RATE_LIMIT_REDIS_URL')
      ? 'YES'
      : 'NO',
    note: 'ECS validation requires AWS CLI + staging ECS read access; never log Redis URL.',
  },
};

process.stdout.write(`${JSON.stringify(matrix, null, 2)}\n`);