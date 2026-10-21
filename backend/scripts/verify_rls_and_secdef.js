const { Client } = require(require('path').join(__dirname, '../node_modules/pg'));
const connectionString = process.env.SUPABASE_DB_URL || 'postgres://postgres:postgres@127.0.0.1:54322/postgres';

async function verify() {
  const client = new Client({ connectionString });
  await client.connect();

  console.log('--- 1. VERIFY 100% RLS ON ALL PUBLIC TABLES ---');
  const rlsRes = await client.query(`
    SELECT relname 
    FROM pg_class 
    WHERE relkind = 'r' 
      AND relnamespace = 'public'::regnamespace 
      AND NOT relrowsecurity
    ORDER BY relname ASC;
  `);

  if (rlsRes.rows.length === 0) {
    console.log('PASS: 100% of public tables have Row-Level Security enabled. Unsecured tables: 0');
  } else {
    console.error(`FAIL: Found ${rlsRes.rows.length} unsecured tables:`, rlsRes.rows.map(r => r.relname));
    process.exit(1);
  }

  console.log('\n--- 2. VERIFY SECURITY DEFINER SEARCH PATH LOCKDOWN ---');
  const secdefRes = await client.query(`
    SELECT 
      p.proname,
      p.prosecdef,
      p.proconfig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' 
      AND p.prosecdef = true
    ORDER BY p.proname ASC;
  `);

  console.log(`Found ${secdefRes.rows.length} SECURITY DEFINER functions in public schema.`);
  let failed = 0;
  for (const fn of secdefRes.rows) {
    const configs = fn.proconfig || [];
    const hasSearchPath = configs.some(c => c.startsWith('search_path='));
    if (!hasSearchPath) {
      console.error(`FAIL: Function ${fn.proname} lacks explicit search_path in proconfig.`);
      failed++;
    }
  }

  if (failed === 0) {
    console.log(`PASS: All ${secdefRes.rows.length} SECURITY DEFINER functions have explicit search_path protection.`);
  } else {
    process.exit(1);
  }

  await client.end();
}

verify().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
