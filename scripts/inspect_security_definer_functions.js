const { Client } = require('pg');
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
const dbUrl = migEnv.PROD_SUPABASE_DB_URL || migEnv.STAGING_SUPABASE_DB_URL;

async function inspectFunctions() {
  const client = new Client({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
  await client.connect();

  const query = `
    SELECT 
      n.nspname as schema,
      p.proname as name,
      pg_get_function_identity_arguments(p.oid) as args,
      p.prosecdef as is_security_definer,
      p.proconfig as config,
      p.proacl as acl,
      pg_get_functiondef(p.oid) as definition
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname IN ('public', 'private')
      AND p.prosecdef = true
    ORDER BY n.nspname, p.proname;
  `;

  const res = await client.query(query);
  console.log(`Found ${res.rows.length} SECURITY DEFINER functions in public and private schemas:`);

  const report = [];
  for (const row of res.rows) {
    const def = row.definition;
    const hasSearchPath = (row.config && row.config.some(c => c.startsWith('search_path='))) || def.includes('SET search_path');
    const checksAuth = def.includes('auth.uid()') || def.includes('auth.jwt()') || def.includes('request.jwt.claims') || def.includes('current_profile_id') || def.includes('is_super_admin');
    
    report.push({
      schema: row.schema,
      name: row.name,
      args: row.args,
      searchPathConfigured: hasSearchPath,
      checksAuthInBody: checksAuth,
      acl: row.acl ? (Array.isArray(row.acl) ? row.acl.join(', ') : String(row.acl)) : 'default (PUBLIC)'
    });
  }

  console.table(report);
  fs.writeFileSync('scripts/security_definer_functions_report.json', JSON.stringify(res.rows, null, 2));
  console.log('Detailed definitions saved to scripts/security_definer_functions_report.json');

  await client.end();
}

inspectFunctions().catch(console.error);
