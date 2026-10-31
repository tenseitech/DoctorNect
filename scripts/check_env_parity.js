#!/usr/bin/env node
/**
 * scripts/check_env_parity.js
 *
 * Scans code (backend/functions, frontend/lib) for environment variable references
 * and compares them against .env.example templates.
 *
 * STRICT SECURITY RULES:
 * 1. NEVER inspects, reads, prints, or logs actual secret values.
 * 2. Only variable names and their structural presence (MISSING, DOCUMENTED, EXTRA) are reported.
 * 3. Does not run any remote commands or touch deployed environments.
 */

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');

// Standard runtime / cloud platform env vars provided by Node.js or GCP/Firebase runtimes
const SYSTEM_ENV_VARS = new Set([
  'NODE_ENV',
  'PORT',
  'PATH',
  'PWD',
  'HOME',
  'K_SERVICE',
  'K_REVISION',
  'K_CONFIGURATION',
  'FIREBASE_CONFIG',
  'GCLOUD_PROJECT',
  'GOOGLE_CLOUD_PROJECT',
  'FUNCTION_NAME',
  'FUNCTION_TARGET',
  'FUNCTION_SIGNATURE_TYPE',
  'FUNCTIONS_EMULATOR',
  'ENTRY_POINT',
  'CLOUD_ML_PROJECT_ID',
  'GOOGLE_APPLICATION_CREDENTIALS',
  'CI',
  'npm_config_devdir',
]);

// Test-only emulator / mock variables used in test files
const TEST_ONLY_VARS = new Set([
  'FIRESTORE_EMULATOR_HOST',
  'FIREBASE_STORAGE_EMULATOR_HOST',
  'LOCAL_DOCKER_PG_URL',
  'FIRESTORE_BASE_URL',
  'GOOGLE_OAUTH_TOKEN_URL',
  'SIMULATE_APPT_WRITE_FAIL',
]);

// Documented legacy aliases that fallback to primary canonical environment variables
const LEGACY_ALIASES = {
  MSG91_AUTHKEY: 'MSG91_AUTH_KEY',
  AUTH_KEY: 'MSG91_AUTH_KEY',
  SUPABASE_SECRET_KEY: 'SUPABASE_SERVICE_ROLE_KEY',
  SUPABASE_SERVICE_KEY: 'SUPABASE_SERVICE_ROLE_KEY',
  CUTOVER_DOCTOR_PATIENT: 'USE_SUPABASE_DB_DOCTOR_PATIENT',
  GOOGLE_PLAY_REVIEW_PHONE: 'DEMO_PHONE_PATIENT',
  MSG91_SENDER: 'MSG91_SENDER_ID',
  REDIS_URL: 'REDIS_HOST',
};

// Ad-hoc script variables used exclusively in developer CLI maintenance tools
const DEV_SCRIPT_VARS = new Set([
  'BOOKING_ID',
  'DOCTOR_EMAIL',
  'DOCTOR_ID',
  'DOCTOR_PASSWORD',
  'FIREBASE_PROJECT_ID',
  'FIREBASE_WEB_API_KEY',
  'NOTIF_DOC_ID',
  'ALLOW_DEMO_SEED',
  'CONFIRM_PROD_SEED',
  'APP_ENV',
  'ENVIRONMENT',
  'FIREBASE_ENV',
  'SUPABASE_ENV',
  'STAGING_SUPABASE_URL',
  'STAGING_SUPABASE_DB_URL',
]);

function getFilesRecursive(dir, extensions, ignoreDirs = ['node_modules', '.git', 'build', '.dart_tool', '.vscode']) {
  let results = [];
  if (!fs.existsSync(dir)) return results;

  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isDirectory()) {
      if (!ignoreDirs.includes(entry.name)) {
        results = results.concat(getFilesRecursive(path.join(dir, entry.name), extensions, ignoreDirs));
      }
    } else if (extensions.some(ext => entry.name.endsWith(ext))) {
      results.push(path.join(dir, entry.name));
    }
  }
  return results;
}

function parseEnvExampleKeys(filePath) {
  const keys = new Set();
  if (!fs.existsSync(filePath)) return keys;

  const content = fs.readFileSync(filePath, 'utf8');
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=/);
    if (match) {
      keys.add(match[1]);
    }
  }
  return keys;
}

function extractJsEnvVars(files) {
  const vars = new Map(); // varName -> Set of files
  const regexDot = /process\.env\.([A-Za-z0-9_]+)/g;
  const regexBracket = /process\.env\[['"`]([A-Za-z0-9_]+)['"`]\]/g;

  for (const file of files) {
    const relFile = path.relative(ROOT_DIR, file).replace(/\\/g, '/');
    const content = fs.readFileSync(file, 'utf8');

    let m;
    while ((m = regexDot.exec(content)) !== null) {
      const v = m[1];
      if (!SYSTEM_ENV_VARS.has(v)) {
        if (!vars.has(v)) vars.set(v, new Set());
        vars.get(v).add(relFile);
      }
    }
    while ((m = regexBracket.exec(content)) !== null) {
      const v = m[1];
      if (!SYSTEM_ENV_VARS.has(v)) {
        if (!vars.has(v)) vars.set(v, new Set());
        vars.get(v).add(relFile);
      }
    }
  }
  return vars;
}

function extractDartEnvVars(files) {
  const vars = new Map(); // varName -> Set of files
  const regexFromEnv = /(?:String|bool|int)\.fromEnvironment\(\s*['"]([A-Za-z0-9_]+)['"]/g;
  const regexPlatformEnv = /Platform\.environment\[\s*['"]([A-Za-z0-9_]+)['"]\s*\]/g;

  for (const file of files) {
    const relFile = path.relative(ROOT_DIR, file).replace(/\\/g, '/');
    const content = fs.readFileSync(file, 'utf8');

    let m;
    while ((m = regexFromEnv.exec(content)) !== null) {
      const v = m[1];
      if (!vars.has(v)) vars.set(v, new Set());
      vars.get(v).add(relFile);
    }
    while ((m = regexPlatformEnv.exec(content)) !== null) {
      const v = m[1];
      if (!SYSTEM_ENV_VARS.has(v)) {
        if (!vars.has(v)) vars.set(v, new Set());
        vars.get(v).add(relFile);
      }
    }
  }
  return vars;
}

function checkEnvParity() {
  console.log('================================================================');
  console.log('  DoctorNect Environment Variable Parity & Security Validator   ');
  console.log('  STRICT POLICY: Zero secret values are ever accessed or printed ');
  console.log('================================================================\n');

  // 1. Gather declared keys across all .env.example files
  const exampleFiles = [
    path.join(ROOT_DIR, '.env.example'),
    path.join(ROOT_DIR, 'backend', 'functions', '.env.example'),
    path.join(ROOT_DIR, 'frontend', '.env.example'),
  ];

  const declaredInExamples = new Map(); // key -> list of files
  for (const ef of exampleFiles) {
    const rel = path.relative(ROOT_DIR, ef).replace(/\\/g, '/');
    const keys = parseEnvExampleKeys(ef);
    for (const k of keys) {
      if (!declaredInExamples.has(k)) declaredInExamples.set(k, []);
      declaredInExamples.get(k).push(rel);
    }
  }

  // 2. Scan production/runtime codebase
  const backendJsFiles = getFilesRecursive(path.join(ROOT_DIR, 'backend', 'functions'), ['.js']);
  const frontendDartFiles = getFilesRecursive(path.join(ROOT_DIR, 'frontend', 'lib'), ['.dart']);

  const jsVars = extractJsEnvVars(backendJsFiles);
  const dartVars = extractDartEnvVars(frontendDartFiles);

  const codeVars = new Map();
  for (const [v, files] of jsVars.entries()) {
    if (!codeVars.has(v)) codeVars.set(v, new Set());
    files.forEach(f => codeVars.get(v).add(f));
  }
  for (const [v, files] of dartVars.entries()) {
    if (!codeVars.has(v)) codeVars.set(v, new Set());
    files.forEach(f => codeVars.get(v).add(f));
  }

  console.log(`Discovered ${declaredInExamples.size} variables documented across .env.example templates.`);
  console.log(`Discovered ${codeVars.size} environment variable references in source code.\n`);

  // 3. Classify variables
  const missingCoreVars = [];
  const recognizedAliases = [];
  const recognizedTestVars = [];
  const recognizedDevScriptVars = [];

  for (const [varName, files] of codeVars.entries()) {
    if (declaredInExamples.has(varName)) {
      // Documented directly
      continue;
    }

    if (LEGACY_ALIASES[varName]) {
      const canonical = LEGACY_ALIASES[varName];
      recognizedAliases.push({ name: varName, canonical, documented: declaredInExamples.has(canonical) });
      continue;
    }

    if (TEST_ONLY_VARS.has(varName)) {
      recognizedTestVars.push({ name: varName, files: Array.from(files) });
      continue;
    }

    if (DEV_SCRIPT_VARS.has(varName)) {
      recognizedDevScriptVars.push({ name: varName, files: Array.from(files) });
      continue;
    }

    // Truly undocumented production / runtime variable
    missingCoreVars.push({ name: varName, files: Array.from(files) });
  }

  // Extra in templates (documented but unreferenced in scanned files)
  const extraInExamples = [];
  for (const [exampleVar, files] of declaredInExamples.entries()) {
    if (!codeVars.has(exampleVar)) {
      extraInExamples.push({ name: exampleVar, files });
    }
  }

  // Reporting
  if (missingCoreVars.length > 0) {
    console.log('❌ CRITICAL: Missing from .env.example (Production code uses these but they are undocumented):');
    missingCoreVars.sort((a, b) => a.name.localeCompare(b.name)).forEach(item => {
      console.log(`   - ${item.name} (referenced in: ${item.files.slice(0, 3).join(', ')})`);
    });
    console.log('');
  } else {
    console.log('✅ ALL core production & runtime variables are documented in .env.example templates!\n');
  }

  if (recognizedAliases.length > 0) {
    console.log('ℹ️  Legacy Aliases (Fallbacks to documented canonical variables):');
    recognizedAliases.sort((a, b) => a.name.localeCompare(b.name)).forEach(item => {
      console.log(`   - ${item.name} -> maps to canonical ${item.canonical} (${item.documented ? 'DOCUMENTED' : 'MISSING'})`);
    });
    console.log('');
  }

  if (recognizedTestVars.length > 0) {
    console.log('ℹ️  Test/Emulator-only mocks (Not needed in production .env):');
    recognizedTestVars.sort((a, b) => a.name.localeCompare(b.name)).forEach(item => {
      console.log(`   - ${item.name}`);
    });
    console.log('');
  }

  if (recognizedDevScriptVars.length > 0) {
    console.log('ℹ️  Ad-hoc maintenance CLI variables (scripts/*.js):');
    recognizedDevScriptVars.sort((a, b) => a.name.localeCompare(b.name)).forEach(item => {
      console.log(`   - ${item.name}`);
    });
    console.log('');
  }

  console.log('----------------------------------------------------------------');
  console.log(`Summary: ${missingCoreVars.length} undocumented core variables.`);
  console.log('----------------------------------------------------------------\n');

  if (missingCoreVars.length > 0) {
    process.exitCode = 1;
  }
}

if (require.main === module) {
  checkEnvParity();
}

module.exports = {
  checkEnvParity,
  parseEnvExampleKeys,
  extractJsEnvVars,
  extractDartEnvVars,
  SYSTEM_ENV_VARS,
  LEGACY_ALIASES,
  TEST_ONLY_VARS,
  DEV_SCRIPT_VARS,
};
