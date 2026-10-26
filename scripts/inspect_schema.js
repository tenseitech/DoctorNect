/**
 * Read-only schema inspector for Supabase PostgreSQL.
 * Queries:
 * 1. Public tables without RLS
 * 2. Public tables with RLS but zero policies
 * 3. Public views and security_invoker status
 * 4. SECURITY DEFINER functions and EXECUTE permissions
 * 5. Current grants for 'anon' and 'authenticated'
 */
const fs = require('fs');
const path = require('path');
const { Client } = require(path.join(__dirname, '../backend/node_modules/pg'));

function loadDbUrl() {
  const envPath = path.join(__dirname, '../.env.migration');
  if (!fs.existsSync(envPath)) {
    throw new Error('.env.migration file missing');
  }
  const lines = fs.readFileSync(envPath, 'utf8').split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx !== -1) {
      const key = trimmed.slice(0, idx).trim();
      const val = trimmed.slice(idx + 1).trim();
      if (key === 'STAGING_SUPABASE_DB_URL' || key === 'SUPABASE_DB_URL') {
        return val;
      }
    }
  }
  throw new Error('No DB URL found in .env.migration');
}

async function inspect() {
  const dbUrl = loadDbUrl();
  const client = new Client({
    connectionString: dbUrl,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  try {
    console.log('Connected to database (read-only query mode).');

    // 1. Tables without RLS
    const noRlsRes = await client.query(`
      SELECT c.relname AS table_name
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relkind = 'r'
        AND NOT c.relrowsecurity
      ORDER BY c.relname;
    `);
    console.log('\n--- 1. Public Tables WITHOUT RLS ---');
    console.log(JSON.stringify(noRlsRes.rows.map(r => r.table_name), null, 2));

    // 2. Tables with RLS but 0 policies
    const rlsNoPolicyRes = await client.query(`
      SELECT c.relname AS table_name
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relkind = 'r'
        AND c.relrowsecurity
        AND NOT EXISTS (
          SELECT 1 FROM pg_policy pol WHERE pol.polrelid = c.oid
        )
      ORDER BY c.relname;
    `);
    console.log('\n--- 2. Public Tables with RLS but ZERO Policies ---');
    console.log(JSON.stringify(rlsNoPolicyRes.rows.map(r => r.table_name), null, 2));

    // 3. Views and security_invoker
    const viewsRes = await client.query(`
      SELECT c.relname AS view_name,
             c.reloptions
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relkind IN ('v', 'm')
      ORDER BY c.relname;
    `);
    console.log('\n--- 3. Public Views (security_invoker status) ---');
    const views = viewsRes.rows.map(r => {
      const opts = r.reloptions || [];
      const isInvoker = opts.some(opt => opt.includes('security_invoker=true'));
      return { view_name: r.view_name, reloptions: opts, security_invoker: isInvoker };
    });
    console.log(JSON.stringify(views, null, 2));

    // 4. SECURITY DEFINER functions
    const secDefRes = await client.query(`
      SELECT p.proname AS function_name,
             pg_get_function_identity_arguments(p.oid) as args,
             pg_get_userbyid(p.proowner) AS owner,
             p.prosecdef AS is_security_definer,
             p.proacl
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.prosecdef = true
      ORDER BY p.proname;
    `);
    console.log('\n--- 4. SECURITY DEFINER Functions and Privileges ---');
    console.log(JSON.stringify(secDefRes.rows.map(r => ({
      name: r.function_name,
      args: r.args,
      owner: r.owner,
      acl: r.proacl
    })), null, 2));

    const grantsRes = await client.query(`
      SELECT table_name, grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) as privileges
      FROM information_schema.role_table_grants
      WHERE table_schema = 'public'
        AND grantee IN ('anon', 'authenticated')
      GROUP BY table_name, grantee
      ORDER BY table_name, grantee;
    `);

    const results = {
      tablesWithoutRls: noRlsRes.rows.map(r => r.table_name),
      tablesWithRlsZeroPolicies: rlsNoPolicyRes.rows.map(r => r.table_name),
      views,
      securityDefinerFunctions: secDefRes.rows.map(r => ({
        name: r.function_name,
        args: r.args,
        owner: r.owner,
        acl: r.proacl
      })),
      grants: grantsRes.rows
    };

    fs.writeFileSync(path.join(__dirname, 'schema_inspection_results.json'), JSON.stringify(results, null, 2));
    console.log('Inspection results saved to scripts/schema_inspection_results.json');
  } finally {
    await client.end();
  }
}

inspect().catch(err => {
  console.error('Inspection failed:', err.message);
  process.exit(1);
});
