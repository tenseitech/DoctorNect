'use strict';

/**
 * Local .env maintenance — never prints secret values.
 * Usage: node scripts/db/safe_env_local_fix.js
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');

const ENV_FILES = [
  path.join(ROOT, '.env'),
  path.join(ROOT, '.env.migration'),
  path.join(ROOT, 'backend/functions/.env'),
  path.join(ROOT, 'services/api-gateway/.env'),
  path.join(ROOT, 'frontend/.env'),
];

const REQUIRED_VARS = [
  'APP_ENV',
  'STAGING_SUPABASE_URL',
  'STAGING_SUPABASE_ANON_KEY',
  'STAGING_SUPABASE_SERVICE_ROLE_KEY',
  'STAGING_SUPABASE_DB_URL',
  'FIREBASE_PROJECT_ID',
  'PROD_GATEWAY_URL',
  'PROD_GATEWAY_ANON_KEY',
  'PROD_GATEWAY_SERVICE_KEY',
  'PROD_RDS_HOST',
  'PROD_RDS_PORT',
  'PROD_RDS_DB',
  'PROD_RDS_USER',
  'PROD_RDS_PASSWORD',
  'PROD_RDS_SSL_ROOT_CERT',
  'REPLAY_DB_URL',
  'PGRST_URL',
  'PGRST_JWT_SECRET',
  'PGRST_JWT_AUD',
  'SERVICE_ROLE_KEY',
  'ANON_KEY',
  'FIREBASE_REVOCATION_CHECK',
  'CORS_ALLOWED_ORIGINS',
  'MSG91_AUTH_KEY',
  'MSG91_SENDER_ID',
  'MSG91_TEMPLATE_ID',
  'REDIS_HOST',
  'REDIS_PASSWORD',
  'AWS_REGION',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'S3_BUCKET',
];

const PLACEHOLDER_COMMENTS = {
  APP_ENV: 'staging for local DB scripts',
  STAGING_SUPABASE_URL: 'staging PostgREST base',
  STAGING_SUPABASE_ANON_KEY: 'staging anon JWT',
  STAGING_SUPABASE_SERVICE_ROLE_KEY: 'staging service role',
  STAGING_SUPABASE_DB_URL: 'session pooler :5432 (see ENV_MATRIX)',
  PROD_GATEWAY_URL: 'production only',
  PROD_GATEWAY_ANON_KEY: 'production only',
  PROD_GATEWAY_SERVICE_KEY: 'production only',
  PROD_RDS_HOST: 'production RDS only',
  PROD_RDS_PORT: 'production RDS only',
  PROD_RDS_DB: 'production RDS only',
  PROD_RDS_USER: 'production RDS only',
  PROD_RDS_PASSWORD: 'production RDS only',
  PROD_RDS_SSL_ROOT_CERT: 'production RDS CA path',
  REPLAY_DB_URL: 'optional local replay DB',
  PGRST_URL: 'gateway upstream PostgREST',
  PGRST_JWT_SECRET: 'gateway JWT secret',
  PGRST_JWT_AUD: 'gateway JWT audience',
  SERVICE_ROLE_KEY: 'gateway service key',
  ANON_KEY: 'gateway anon key',
};

function parseEnvLines(content) {
  return content.split(/\r?\n/);
}

function parseKeyFromLine(line) {
  const t = line.trim();
  if (!t || t.startsWith('#')) return null;
  const eq = t.indexOf('=');
  if (eq === -1) return null;
  return t.slice(0, eq).trim();
}

function unquoteValue(raw) {
  let v = raw.trim();
  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
    v = v.slice(1, -1);
  }
  return v;
}

function patchStagingDbUrlValue(rawVal) {
  let changed = false;
  let v = unquoteValue(rawVal);
  if (!v) return { value: rawVal, changed: false, meta: null };
  try {
    const u = new URL(v.replace(/^postgres:\/\//i, 'postgresql://'));
    if (u.port === '6543') {
      u.port = '5432';
      changed = true;
    }
    if (u.searchParams.has('sslmode')) {
      u.searchParams.delete('sslmode');
      changed = true;
    }
    const out = u.toString().replace(/^postgresql:\/\//i, 'postgres://');
    const meta = {
      host: u.hostname,
      port: u.port || '5432',
      database: u.pathname.replace(/^\//, '') || 'postgres',
      user: u.username ? u.username.split('.')[0] : '',
    };
    return { value: out, changed, meta };
  } catch (_) {
    return { value: v, changed: false, meta: null };
  }
}

function maskMeta(meta) {
  if (!meta) return '(parse failed — check format manually)';
  return `host=${meta.host} port=${meta.port} db=${meta.database} user=${meta.user || '****'} password=****`;
}

function patchFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return { file: filePath, exists: false, stagingChanged: false, meta: null };
  }
  const lines = parseEnvLines(fs.readFileSync(filePath, 'utf8'));
  let stagingChanged = false;
  let meta = null;
  const newLines = lines.map((line) => {
    const key = parseKeyFromLine(line);
    if (key !== 'STAGING_SUPABASE_DB_URL') return line;
    const eq = line.indexOf('=');
    const rawVal = line.slice(eq + 1);
    const { value, changed, meta: m } = patchStagingDbUrlValue(rawVal);
    if (changed) stagingChanged = true;
    if (m) meta = m;
    return `${key}=${value}`;
  });
  if (stagingChanged) {
    fs.writeFileSync(filePath, newLines.join('\n'), 'utf8');
  }
  return {
    file: path.relative(ROOT, filePath),
    exists: true,
    stagingChanged,
    meta,
  };
}

function loadMergedEnv() {
  const merged = { ...process.env };
  for (const fp of ENV_FILES) {
    if (!fs.existsSync(fp)) continue;
    const lines = parseEnvLines(fs.readFileSync(fp, 'utf8'));
    for (const line of lines) {
      const key = parseKeyFromLine(line);
      if (!key) continue;
      const eq = line.indexOf('=');
      merged[key] = unquoteValue(line.slice(eq + 1));
    }
  }
  return merged;
}

function hostnameOf(urlOrHost) {
  if (!urlOrHost) return '';
  const s = urlOrHost.trim();
  if (!s) return '';
  try {
    if (s.includes('://')) {
      return new URL(s.replace(/^postgres:\/\//i, 'postgresql://')).hostname.toLowerCase();
    }
    return s.split(':')[0].toLowerCase();
  } catch (_) {
    return '';
  }
}

function supabaseProjectRef(stagingUrl) {
  const h = hostnameOf(stagingUrl);
  const m = h.match(/^([a-z0-9]+)\.supabase\.co$/i);
  return m ? m[1].toLowerCase() : '';
}

function hostLooksLikeSupabase(host) {
  if (!host) return false;
  return host.includes('supabase.co') || host.includes('pooler.supabase.com');
}

function hostLooksLikeRds(host) {
  if (!host) return false;
  return host.includes('rds.amazonaws.com');
}

function isolationChecks(env) {
  const ref = supabaseProjectRef(env.STAGING_SUPABASE_URL || env.STAGING_SUPABASE_DB_URL);
  const results = [];

  const stagingDbHost = hostnameOf(env.STAGING_SUPABASE_DB_URL);
  results.push({
    name: 'STAGING_SUPABASE_DB_URL_not_rds',
    pass: !hostLooksLikeRds(stagingDbHost),
  });
  results.push({
    name: 'STAGING_SUPABASE_DB_URL_not_empty',
    pass: Boolean(stagingDbHost),
  });

  const stagingApiHost = hostnameOf(env.STAGING_SUPABASE_URL);
  results.push({
    name: 'STAGING_SUPABASE_URL_not_rds',
    pass: !stagingApiHost || !hostLooksLikeRds(stagingApiHost),
  });

  const prodRds = hostnameOf(env.PROD_RDS_HOST);
  results.push({
    name: 'PROD_RDS_HOST_not_supabase',
    pass: !prodRds || !hostLooksLikeSupabase(prodRds),
  });
  results.push({
    name: 'PROD_RDS_HOST_not_staging_ref',
    pass: !ref || !prodRds || !prodRds.includes(ref),
  });

  const prodGw = hostnameOf(env.PROD_GATEWAY_URL);
  results.push({
    name: 'PROD_GATEWAY_URL_not_supabase',
    pass: !prodGw || !hostLooksLikeSupabase(prodGw),
  });

  const prodDbUrlHost = hostnameOf(env.PROD_SUPABASE_DB_URL || '');
  if (prodDbUrlHost) {
    results.push({
      name: 'PROD_SUPABASE_DB_URL_not_staging_pooler',
      pass: ref ? !prodDbUrlHost.includes(ref) : true,
    });
  }

  return results;
}

function ensureMissingVars(targetFile) {
  if (!fs.existsSync(targetFile)) {
    fs.writeFileSync(targetFile, '# Auto-added placeholders — fill manually\n', 'utf8');
  }
  const content = fs.readFileSync(targetFile, 'utf8');
  const lines = parseEnvLines(content);
  const present = new Set();
  for (const line of lines) {
    const k = parseKeyFromLine(line);
    if (k) present.add(k);
  }
  const mergedBefore = loadMergedEnv();
  const added = [];
  const append = [];
  for (const name of REQUIRED_VARS) {
    if (present.has(name)) continue;
    if (mergedBefore[name]) continue;
    const comment = PLACEHOLDER_COMMENTS[name] || 'see ENV_MATRIX.md';
    append.push(`# ${comment}`);
    append.push(`${name}=`);
    added.push(name);
  }
  if (append.length) {
    const sep = content.endsWith('\n') || content.length === 0 ? '' : '\n';
    fs.writeFileSync(targetFile, content + sep + append.join('\n') + '\n', 'utf8');
  }
  return added;
}

function main() {
  console.log('=== safe_env_local_fix (no secret values) ===\n');

  const patchResults = [];
  for (const fp of ENV_FILES) {
    const r = patchFile(fp);
    if (!r.exists) continue;
    patchResults.push(r);
    console.log(
      `STAGING_SUPABASE_DB_URL in ${r.file}: changed=${r.stagingChanged ? 'yes' : 'no'}`,
    );
    if (r.stagingChanged || r.meta) {
      console.log(`  masked: ${maskMeta(r.meta)}`);
    }
  }

  const targetForAdd = fs.existsSync(path.join(ROOT, '.env.migration'))
    ? path.join(ROOT, '.env.migration')
    : path.join(ROOT, '.env');
  const added = ensureMissingVars(targetForAdd);
  if (added.length) {
    console.log(`\nPlaceholders appended to ${path.relative(ROOT, targetForAdd)}:`);
    for (const n of added) console.log(`  + ${n}`);
  }

  const merged = loadMergedEnv();
  const missing = REQUIRED_VARS.filter((k) => !merged[k]);
  const empty = REQUIRED_VARS.filter((k) => merged[k] === '');

  console.log('\n--- Presence (names only) ---');
  for (const k of REQUIRED_VARS) {
    if (!merged[k]) console.log(`MISSING ${k}`);
    else if (merged[k] === '') console.log(`EMPTY ${k}`);
    else console.log(`OK ${k}`);
  }

  console.log('\n--- Staging vs production isolation ---');
  for (const r of isolationChecks(merged)) {
    console.log(`${r.pass ? 'PASS' : 'FAIL'} ${r.name}`);
  }

  const perFile = {};
  for (const fp of ENV_FILES) {
    if (!fs.existsSync(fp)) {
      perFile[path.relative(ROOT, fp)] = 'absent';
      continue;
    }
    const present = new Set();
    for (const line of parseEnvLines(fs.readFileSync(fp, 'utf8'))) {
      const k = parseKeyFromLine(line);
      if (k) present.add(k);
    }
    const miss = REQUIRED_VARS.filter((k) => !present.has(k));
    perFile[path.relative(ROOT, fp)] = miss.length ? miss.join(',') : 'all_required_keys_present';
  }
  console.log('\n--- Per-file key coverage (missing names only) ---');
  for (const [f, status] of Object.entries(perFile)) {
    console.log(`${f}: ${status}`);
  }

  return { patchResults, added, missing, empty };
}

main();
