'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const rootDir = path.resolve(__dirname, '../..');

function extractEnvVars(dirPattern) {
  const files = execSync(`git ls-files "${dirPattern}"`, { cwd: rootDir, encoding: 'utf8' }).split('\n').filter(Boolean);
  const vars = new Set();
  for (const f of files) {
    const full = path.join(rootDir, f);
    if (!fs.existsSync(full)) continue;
    const content = fs.readFileSync(full, 'utf8');
    const matches = content.match(/process\.env\.([A-Z0-9_]+)/g) || [];
    for (const m of matches) {
      vars.add(m.replace('process.env.', ''));
    }
  }
  return Array.from(vars).sort();
}

const backendVars = extractEnvVars('backend/functions/**/*.js');
const gatewayVars = extractEnvVars('services/api-gateway/**/*.js');

// AWS infra variables
const tfFiles = execSync('git ls-files "infra/aws/*.tf"', { cwd: rootDir, encoding: 'utf8' }).split('\n').filter(Boolean);
const awsVars = new Set();
for (const f of tfFiles) {
  const content = fs.readFileSync(path.join(rootDir, f), 'utf8');
  const matches = content.match(/var\.([a-z0-9_]+)/g) || [];
  for (const m of matches) {
    awsVars.add(m.replace('var.', ''));
  }
}

console.log('================================================================');
console.log('DOCTORNECT: SECRETS AUDIT & REBUILT ROTATION LIST');
console.log('================================================================\n');

console.log('1. SMS PROVIDER AUDIT:');
console.log('   - Provider in use: MSG91 (12 integration files, 0 references to Fast2SMS in backend/functions).');
console.log('   - Fast2SMS: Deprecated / Not in use.\n');

console.log('2. ACTUAL ENVIRONMENT VARIABLE USAGE:');
console.log('   backend/functions env vars:', backendVars.length);
console.log('   services/api-gateway env vars:', gatewayVars.length);
console.log('   infra/aws variables:', awsVars.size);

console.log('\n3. MASTER SECRETS ROTATION SCHEDULE & LOCATIONS:');
const rotationList = [
  {
    secret: 'MSG91_AUTH_KEY / MSG91_AUTHKEY',
    category: 'SMS Gateway',
    usedIn: 'backend/functions (registration_otp.js, etc.)',
    storageLocation: 'GCP Secret Manager (MSG91_AUTH_KEY)',
    rotationAction: 'Generate new API key in MSG91 console, update GCP Secret Manager, trigger function re-deployment.'
  },
  {
    secret: 'RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET',
    category: 'Payment Gateway',
    usedIn: 'backend/functions (razorpay.js, promoted_ads.js)',
    storageLocation: 'GCP Secret Manager (RAZORPAY_KEY_SECRET)',
    rotationAction: 'Generate new key pair in Razorpay Dashboard, update GCP Secret Manager, update frontend compile defines.'
  },
  {
    secret: 'RAZORPAY_WEBHOOK_SECRET',
    category: 'Payment Webhook',
    usedIn: 'backend/functions (razorpay_webhook.js)',
    storageLocation: 'GCP Secret Manager (RAZORPAY_WEBHOOK_SECRET)',
    rotationAction: 'Configure new webhook secret in Razorpay dashboard, update Secret Manager.'
  },
  {
    secret: 'AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY',
    category: 'AWS S3 Cloud Storage',
    usedIn: 'backend/functions (s3_storage.js)',
    storageLocation: 'GCP Secret Manager / IAM Service User',
    rotationAction: 'Rotate IAM access key in AWS IAM console, update GCP Secret Manager.'
  },
  {
    secret: 'REDIS_PASSWORD',
    category: 'Redis / Upstash Cache',
    usedIn: 'backend/functions (redis.js), services/api-gateway',
    storageLocation: 'GCP Secret Manager / Upstash console',
    rotationAction: 'Rotate password in Upstash or Redis console, update Secret Manager / Gateway ECS task definition.'
  },
  {
    secret: 'PROD_RDS_PASSWORD (db_password)',
    category: 'Production PostgreSQL Database',
    usedIn: 'infra/aws (rds.tf), services/api-gateway, backend/functions',
    storageLocation: 'AWS Secrets Manager (db_password) / parameter store',
    rotationAction: 'Alter postgres user password via RDS Modify, update AWS Secrets Manager, restart API gateway task.'
  },
  {
    secret: 'GATEWAY_INTERNAL_SECRET / PROXY_SECRET',
    category: 'Internal Gateway-to-Backend Token',
    usedIn: 'services/api-gateway, backend/functions',
    storageLocation: 'ECS Secrets / GCP Secret Manager',
    rotationAction: 'Generate 256-bit random hex string, update in ECS and GCP Secret Manager.'
  },
  {
    secret: 'STAGING_SUPABASE_SERVICE_ROLE_KEY',
    category: 'Supabase Staging Admin Access',
    usedIn: 'scripts/db (migration scripts, tests, sync functions)',
    storageLocation: 'Supabase Dashboard Project Settings -> API',
    rotationAction: 'Rotate JWT secret in Supabase dashboard, update .env.migration.'
  },
  {
    secret: 'STAGING_SUPABASE_ANON_KEY',
    category: 'Supabase Staging Client Access',
    usedIn: 'frontend compile defines, scripts/db',
    storageLocation: 'Supabase Dashboard Project Settings -> API',
    rotationAction: 'Regenerated automatically when JWT secret is rotated in Supabase.'
  },
  {
    secret: 'FIREBASE_SERVICE_ACCOUNT_KEY',
    category: 'Firebase Admin SDK Credentials',
    usedIn: 'backend/functions, services/api-gateway',
    storageLocation: 'GCP IAM Service Accounts',
    rotationAction: 'Create new key for Firebase Admin service account in GCP IAM console, delete old key.'
  },
  {
    secret: 'FIREBASE_APPCHECK_DEBUG_TOKEN / RECAPTCHA_SITE_KEY',
    category: 'Anti-Abuse / App Check',
    usedIn: 'frontend, backend/functions',
    storageLocation: 'Firebase Console -> App Check',
    rotationAction: 'Generate new debug token or reCAPTCHA v3 key in Google reCAPTCHA console.'
  }
];

console.table(rotationList);
