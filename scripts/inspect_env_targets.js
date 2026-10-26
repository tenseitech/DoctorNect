const fs = require('fs');

function parseSimpleEnv(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const content = fs.readFileSync(filePath, 'utf8');
  const res = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx > 0) {
      const key = trimmed.slice(0, idx).trim();
      let val = trimmed.slice(idx + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      res[key] = val;
    }
  }
  return res;
}

const migEnv = parseSimpleEnv('.env.migration');
const funcEnv = parseSimpleEnv('backend/functions/.env');
const rootEnv = parseSimpleEnv('.env');

function getHost(url) {
  try {
    return new URL(url).host;
  } catch (e) {
    return 'invalid_url';
  }
}

function getProjectRef(url) {
  try {
    const host = new URL(url).host;
    return host.split('.')[0];
  } catch (e) {
    return 'unknown';
  }
}

function getDbHost(dbUrl) {
  try {
    const parsed = new URL(dbUrl);
    return parsed.host;
  } catch (e) {
    return 'invalid_db_url';
  }
}

console.log('--- Env DB and URL Targets ---');
console.log('.env.migration:');
console.log('  STAGING_SUPABASE_DB_URL host:', getDbHost(migEnv.STAGING_SUPABASE_DB_URL || ''));
console.log('  SUPABASE_URL ref:', getProjectRef(migEnv.SUPABASE_URL || ''));
console.log('  SUPABASE_URL host:', getHost(migEnv.SUPABASE_URL || ''));

console.log('backend/functions/.env:');
console.log('  SUPABASE_URL ref:', getProjectRef(funcEnv.SUPABASE_URL || ''));
console.log('  SUPABASE_URL host:', getHost(funcEnv.SUPABASE_URL || ''));

console.log('.env:');
console.log('  SUPABASE_URL ref:', getProjectRef(rootEnv.SUPABASE_URL || ''));
console.log('  SUPABASE_URL host:', getHost(rootEnv.SUPABASE_URL || ''));

const stagingDbHost = getDbHost(migEnv.STAGING_SUPABASE_DB_URL || '');
const postgrestHost = getHost(funcEnv.SUPABASE_URL || '');
console.log('\n--- Plain Answer to Question 1 ---');
console.log(`STAGING_SUPABASE_DB_URL host: ${stagingDbHost}`);
console.log(`SUPABASE_URL (PostgREST) host: ${postgrestHost}`);
if (stagingDbHost.includes('rnltknemwnjrjxthtull') && postgrestHost.includes('rnltknemwnjrjxthtull')) {
  console.log('VERDICT: STAGING and PRODUCTION point to the SAME database (rnltknemwnjrjxthtull)!');
} else {
  console.log(`VERDICT: They point to different targets: DB host ${stagingDbHost} vs PostgREST host ${postgrestHost}`);
}
