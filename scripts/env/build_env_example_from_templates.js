'use strict';

/**
 * Build unified root .env.example from legacy template files + key union from root .env.
 */

const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { parseEnvFile } = require('../lib/parse_env_file');

const LEGACY = [
  'backend/functions/.env.example',
  'frontend/.env.example',
  'backend/.env.migration.example',
  '.env.migration.example',
  '.env.example',
];

const PLACEHOLDERS = {
  APP_ENV: 'staging',
  STAGING_SUPABASE_URL: 'https://your-project-ref.supabase.co',
  STAGING_SUPABASE_ANON_KEY: 'your-staging-anon-key',
  STAGING_SUPABASE_SERVICE_ROLE_KEY: 'your-staging-service-role-key',
  STAGING_SUPABASE_DB_URL: 'postgresql://postgres.[PROJECT_REF]:[PASSWORD]@aws-0-ap-south-1.pooler.supabase.com:5432/postgres?sslmode=require',
  PROD_GATEWAY_URL: 'https://api.doctornect.com',
  PROD_GATEWAY_ANON_KEY: 'your-production-gateway-anon-key',
  PROD_GATEWAY_SERVICE_KEY: 'your-production-gateway-service-key',
  PROD_RDS_HOST: 'your-db.xxxxx.ap-south-1.rds.amazonaws.com',
  PROD_RDS_CONNECT_HOST: '127.0.0.1',
  PROD_RDS_PORT: '5433',
  PROD_RDS_DB: 'doctornect',
  PROD_RDS_USER: 'postgres',
  PROD_RDS_PASSWORD: '',
  PROD_RDS_SSL_ROOT_CERT: 'infra/aws/global-bundle.pem',
  PROD_RDS_SSLMODE: 'verify-full',
  PROD_RDS_SSL_SERVERNAME: 'your-db.xxxxx.ap-south-1.rds.amazonaws.com',
  FIREBASE_PROJECT_ID: 'medibond-45fad',
  FIREBASE_SERVICE_ACCOUNT_PATH: './scripts/service-account.json',
};

function extractTemplateLines(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const map = {};
  const content = fs.readFileSync(filePath, 'utf8');
  for (const line of content.split(/\r?\n/)) {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (m) map[m[1]] = m[2];
  }
  return map;
}

function main() {
  const root = findRepoRoot();
  const templates = {};
  for (const rel of LEGACY) {
    Object.assign(templates, extractTemplateLines(path.join(root, rel)));
  }
  const envKeys = parseEnvFile(path.join(root, '.env'));
  const allKeys = new Set([...Object.keys(templates), ...Object.keys(envKeys), ...Object.keys(PLACEHOLDERS)]);

  const sections = [
    {
      title: 'APP_ENV — staging vs production routing (Functions, scripts, Flutter build)',
      keys: ['APP_ENV', 'SKIP_APP_ENV_DB_ASSERT'],
    },
    {
      title: 'Firebase (Admin scripts + client dart-defines)',
      keys: [
        'FIREBASE_PROJECT_ID',
        'FIREBASE_SERVICE_ACCOUNT_PATH',
        'FIREBASE_API_KEY_ANDROID',
        'FIREBASE_API_KEY_IOS',
        'FIREBASE_API_KEY_WEB',
        'FIREBASE_STORAGE_BUCKET',
        'FIREBASE_APPCHECK_RECAPTCHA_SITE_KEY',
        'FIREBASE_APPCHECK_DEBUG_TOKEN',
        'RECAPTCHA_SITE_KEY',
        'APP_CHECK_DEBUG_TOKEN',
        'GOOGLE_MAPS_API_KEY',
      ],
    },
    {
      title: 'Staging — Supabase Postgres',
      keys: [
        'STAGING_SUPABASE_URL',
        'STAGING_SUPABASE_ANON_KEY',
        'STAGING_SUPABASE_SERVICE_ROLE_KEY',
        'STAGING_SUPABASE_DB_URL',
        'SUPABASE_URL',
        'SUPABASE_ANON_KEY',
        'SUPABASE_SERVICE_ROLE_KEY',
        'SUPABASE_DB_URL',
        'DATABASE_URL',
        'SUPABASE_WEBHOOK_SECRET',
      ],
    },
    {
      title: 'Production — AWS RDS (operator scripts; tunnel via RDS_PROD_TUNNEL_WINDOWS.md)',
      keys: [
        'PROD_RDS_HOST',
        'PROD_RDS_CONNECT_HOST',
        'PROD_RDS_PORT',
        'PROD_RDS_DB',
        'PROD_RDS_USER',
        'PROD_RDS_PASSWORD',
        'PROD_RDS_SSL_ROOT_CERT',
        'PROD_RDS_SSLMODE',
        'PROD_RDS_SSL_SERVERNAME',
        'REPLAY_DB_URL',
        'LOCAL_FRESH_DB_URL',
        'FRESH_LOCAL_DB_NAME',
      ],
    },
    {
      title: 'Production — Auth Gateway + PostgREST',
      keys: ['PROD_GATEWAY_URL', 'PROD_GATEWAY_SERVICE_KEY', 'PROD_GATEWAY_ANON_KEY', 'PGRST_URL', 'PGRST_JWT_SECRET', 'PGRST_JWT_AUD'],
    },
    {
      title: 'Redis',
      keys: ['REDIS_HOST_STAGING', 'REDIS_HOST_PRODUCTION', 'REDIS_HOST', 'REDIS_PORT', 'REDIS_PASSWORD', 'REDIS_TLS', 'REDIS_CA_CERT', 'REDIS_CA_PATH', 'OTP_REDIS_MIRROR', 'RATE_LIMIT_BACKEND'],
    },
    {
      title: 'AWS S3',
      keys: ['AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_REGION', 'S3_BUCKET_STAGING', 'S3_BUCKET_PRODUCTION', 'S3_BUCKET', 'S3_URL_CACHE', 'USE_S3_STORAGE'],
    },
    {
      title: 'MSG91 OTP',
      keys: [
        'MSG91_AUTH_KEY',
        'MSG91_TEMPLATE_ID',
        'MSG91_TEMPLATE_ID_REGISTRATION',
        'MSG91_TEMPLATE_ID_LOGIN',
        'MSG91_TEMPLATE_ID_PASSWORD_RESET',
        'MSG91_SENDER_ID',
        'MSG91_FROM_EMAIL',
        'MSG91_EMAIL_DOMAIN',
        'MSG91_PROXY_URL',
        'PROXY_SECRET',
        'MSG91_TEMPLATE_ID_APPROVAL',
        'MSG91_TEMPLATE_ID_REJECTION',
        'VPC_CONNECTOR',
        'ALLOW_LEGACY_UNSALTED_OTP_HASH',
        'OTP_TEST_MODE',
        'ENFORCE_OTP_APP_CHECK',
        'ENFORCE_ABUSE_APP_CHECK',
      ],
    },
    {
      title: 'Razorpay',
      keys: ['RAZORPAY_KEY_ID', 'RAZORPAY_KEY_SECRET', 'RAZORPAY_WEBHOOK_SECRET'],
    },
    {
      title: 'Flutter client (dart-define — no server secrets)',
      keys: [
        'ENABLE_SUPABASE',
        'USE_SUPABASE_AUTH',
        'USE_SUPABASE_DB_DOCTOR_PATIENT',
        'FIRESTORE_FORBIDDEN',
        'AMBULANCE_ENABLED',
        'ENABLE_DEMO_AUTH',
        'ENABLE_DEMO_SUPER_ADMIN',
        'ENABLE_SUPABASE_SYNC',
        'FORCE_ENABLE_SUPABASE_SYNC_IN_PROD',
        'ENABLE_REVIEW_DEMO',
      ],
    },
    {
      title: 'Functions ops / review / admin',
      keys: [
        'FIRESTORE_FORBIDDEN',
        'FIRESTORE_TRIGGER_REGION',
        'NOTIFICATION_DISPATCH_MODE',
        'DEMO_PHONE_PATIENT',
        'DEMO_PHONE_DOCTOR',
        'DEMO_PHONE_MEDICAL_STORE',
        'DEMO_PHONE_LAB',
        'DEMO_PHONE_AMBULANCE',
        'DEMO_PHONE_SUPER_ADMIN',
        'REVIEWER_OTP_ENABLED',
        'REVIEW_ACCESS_UNTIL',
        'REVIEW_FIXED_OTP',
        'REVIEW_PATIENT_PHONES',
        'REVIEW_DOCTOR_PHONES',
        'REVIEW_LAB_PHONES',
        'REVIEW_MEDICAL_STORE_PHONES',
        'REVIEW_AMBULANCE_PHONES',
        'ACCOUNT_APPROVAL_ADMIN_EMAILS',
        'PATIENT_APPROVAL_ADMIN_EMAILS',
        'BACKFILL_ADMIN_EMAILS',
        'ADMIN_CONSOLE_CORS_ORIGINS_STAGING',
        'ADMIN_CONSOLE_CORS_ORIGINS_PRODUCTION',
        'ADMIN_CONSOLE_CORS_ORIGINS',
        'ENFORCE_AMBULANCE_HTTP_APP_CHECK',
        'AMBULANCE_HTTP_ALLOWED_ORIGINS',
        'FIRESTORE_TEST_COLLECTION_PREFIX',
      ],
    },
  ];

  const used = new Set();
  const lines = [
    '# =============================================================================',
    '# DoctorNect — single environment template (committed).',
    '# Copy to gitignored `.env` at repo root. Real values never committed.',
    '# =============================================================================',
    '',
  ];

  for (const sec of sections) {
    lines.push(`# --- ${sec.title} ---`);
  for (const key of sec.keys) {
      used.add(key);
      const val = templates[key] ?? PLACEHOLDERS[key] ?? '';
      lines.push(`${key}=${val}`);
    }
    lines.push('');
  }

  const extra = [...allKeys].filter((k) => !used.has(k)).sort();
  if (extra.length) {
    lines.push('# --- Other keys (from legacy templates / local .env) ---');
    for (const key of extra) {
      lines.push(`${key}=${templates[key] ?? PLACEHOLDERS[key] ?? ''}`);
    }
    lines.push('');
  }

  const out = path.join(root, '.env.example');
  fs.writeFileSync(out, `${lines.join('\n')}\n`);
  console.log(`Wrote ${out} (${allKeys.size} unique keys)`);
}

main();
