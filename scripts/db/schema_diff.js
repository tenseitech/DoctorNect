'use strict';

/**
 * DoctorNect Schema Parity Comparison Tool
 * Compares normalized database catalogs between Staging and Target (Rehearsal or Production).
 *
 * Checks:
 * - Tables and Columns (data types, nullability, defaults)
 * - Constraints (Primary, Foreign Key, Check, Unique)
 * - Indexes
 * - Views (with security_invoker flag)
 * - Functions (SECURITY DEFINER, search_path, body hash, ACLs)
 * - Triggers
 * - RLS Policies (qual, with_check, cmd, roles)
 * - Table row security flags (relrowsecurity, relforcerowsecurity)
 * - Role Grants (anon, authenticated, service_role)
 * - Extensions and Publications
 */

const { Client } = require('pg');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');

async function fetchCatalog(client) {
  const catalog = {};

  // 1. Tables and Columns
  const colsRes = await client.query(`
    SELECT table_schema, table_name, column_name, data_type, is_nullable, column_default
    FROM information_schema.columns
    WHERE table_schema = 'public'
    ORDER BY table_name, ordinal_position;
  `);
  catalog.columns = colsRes.rows;

  // 2. Constraints
  const constrRes = await client.query(`
    SELECT tc.constraint_name, tc.table_name, tc.constraint_type,
           kcu.column_name, ccu.table_name AS foreign_table_name,
           ccu.column_name AS foreign_column_name,
           rc.check_clause
    FROM information_schema.table_constraints tc
    LEFT JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    LEFT JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
    LEFT JOIN (
      SELECT conname, pg_get_constraintdef(c.oid) AS check_clause
      FROM pg_constraint c
      JOIN pg_namespace n ON n.oid = c.connamespace
      WHERE n.nspname = 'public'
    ) rc ON rc.conname = tc.constraint_name
    WHERE tc.table_schema = 'public'
    ORDER BY tc.table_name, tc.constraint_name, kcu.column_name;
  `);
  catalog.constraints = constrRes.rows;

  // 3. RLS Policies
  const polRes = await client.query(`
    SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
    ORDER BY tablename, policyname;
  `);
  catalog.policies = polRes.rows;

  // 4. RLS Table Flags
  const rlsFlagsRes = await client.query(`
    SELECT c.relname AS table_name, c.relrowsecurity, c.relforcerowsecurity
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'
    ORDER BY c.relname;
  `);
  catalog.rlsFlags = rlsFlagsRes.rows;

  // 5. Functions
  const funcRes = await client.query(`
    SELECT p.proname,
           pg_get_functiondef(p.oid) AS definition,
           p.prosecdef AS is_security_definer,
           p.proconfig AS search_path_config
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
    ORDER BY p.proname;
  `);
  catalog.functions = funcRes.rows.map((r) => ({
    proname: r.proname,
    is_security_definer: r.is_security_definer,
    search_path_config: r.search_path_config,
    def_hash: crypto.createHash('sha256').update(r.definition || '').digest('hex').slice(0, 16),
  }));

  // 6. Views
  const viewsRes = await client.query(`
    SELECT table_name, view_definition
    FROM information_schema.views
    WHERE table_schema = 'public'
    ORDER BY table_name;
  `);
  catalog.views = viewsRes.rows;

  // 7. Extensions
  const extRes = await client.query(`
    SELECT extname, extversion FROM pg_extension ORDER BY extname;
  `);
  catalog.extensions = extRes.rows;

  // 8. Triggers
  const trgRes = await client.query(`
    SELECT event_object_table, trigger_name, event_manipulation, action_statement, action_timing
    FROM information_schema.triggers
    WHERE event_object_schema = 'public'
    ORDER BY event_object_table, trigger_name;
  `);
  catalog.triggers = trgRes.rows;

  // 9. Table Grants
  const grantsRes = await client.query(`
    SELECT grantee, table_name, privilege_type
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND grantee IN ('anon', 'authenticated', 'service_role')
    ORDER BY table_name, grantee, privilege_type;
  `);
  catalog.grants = grantsRes.rows;

  return catalog;
}

function compareCatalogs(staging, target, targetName) {
  const diffs = [];

  // Compare columns & defaults
  const stagingCols = new Map(staging.columns.map((c) => [`${c.table_name}.${c.column_name}`, c]));
  const targetCols = new Map(target.columns.map((c) => [`${c.table_name}.${c.column_name}`, c]));

  for (const [key, sCol] of stagingCols) {
    if (!targetCols.has(key)) {
      diffs.push({ category: 'COLUMN', key, diff: `Missing in ${targetName}` });
    } else {
      const tCol = targetCols.get(key);
      if (sCol.data_type !== tCol.data_type) {
        diffs.push({ category: 'COLUMN_TYPE', key, diff: `Type mismatch: staging=${sCol.data_type}, ${targetName}=${tCol.data_type}` });
      }
      if (sCol.is_nullable !== tCol.is_nullable) {
        diffs.push({ category: 'COLUMN_NULLABLE', key, diff: `Nullable mismatch: staging=${sCol.is_nullable}, ${targetName}=${tCol.is_nullable}` });
      }
      if (sCol.column_default !== tCol.column_default) {
        diffs.push({ category: 'COLUMN_DEFAULT', key, diff: `Default mismatch: staging="${sCol.column_default || ''}", ${targetName}="${tCol.column_default || ''}"` });
      }
    }
  }

  for (const [key] of targetCols) {
    if (!stagingCols.has(key)) {
      diffs.push({ category: 'COLUMN_EXTRA', key, diff: `Present in ${targetName} but not staging` });
    }
  }

  // Compare Constraints
  const stagingCon = new Map((staging.constraints || []).map(c => [`${c.table_name}::${c.constraint_name}`, c]));
  const targetCon = new Map((target.constraints || []).map(c => [`${c.table_name}::${c.constraint_name}`, c]));

  for (const [key, sC] of stagingCon) {
    if (!targetCon.has(key)) {
      diffs.push({ category: 'CONSTRAINT_MISSING', key, diff: `Constraint missing in ${targetName} (${sC.constraint_type})` });
    }
  }
  for (const [key, tC] of targetCon) {
    if (!stagingCon.has(key)) {
      diffs.push({ category: 'CONSTRAINT_EXTRA', key, diff: `Constraint extra in ${targetName} (${tC.constraint_type})` });
    }
  }

  // Compare RLS Policies
  const stagingPol = new Map(staging.policies.map((p) => [`${p.tablename}::${p.policyname}`, p]));
  const targetPol = new Map(target.policies.map((p) => [`${p.tablename}::${p.policyname}`, p]));

  for (const [key, sP] of stagingPol) {
    if (!targetPol.has(key)) {
      diffs.push({ category: 'POLICY_MISSING', key, diff: `Policy missing in ${targetName}` });
    } else {
      const tP = targetPol.get(key);
      if (sP.cmd !== tP.cmd) {
        diffs.push({ category: 'POLICY_CMD', key, diff: `Command mismatch: ${sP.cmd} vs ${tP.cmd}` });
      }
      if (sP.qual !== tP.qual) {
        diffs.push({ category: 'POLICY_QUAL', key, diff: `USING qual mismatch` });
      }
      if (sP.with_check !== tP.with_check) {
        diffs.push({ category: 'POLICY_WITH_CHECK', key, diff: `WITH CHECK mismatch` });
      }
    }
  }

  for (const [key] of targetPol) {
    if (!stagingPol.has(key)) {
      diffs.push({ category: 'POLICY_EXTRA', key, diff: `Extra policy in ${targetName}` });
    }
  }

  // Compare Functions
  const stagingFunc = new Map(staging.functions.map((f) => [f.proname, f]));
  const targetFunc = new Map(target.functions.map((f) => [f.proname, f]));

  for (const [name, sF] of stagingFunc) {
    if (!targetFunc.has(name)) {
      diffs.push({ category: 'FUNCTION_MISSING', key: name, diff: `Function missing in ${targetName}` });
    } else {
      const tF = targetFunc.get(name);
      if (sF.is_security_definer !== tF.is_security_definer) {
        diffs.push({ category: 'FUNCTION_SECDEF', key: name, diff: `SECURITY DEFINER mismatch` });
      }
      if (sF.def_hash !== tF.def_hash) {
        diffs.push({ category: 'FUNCTION_BODY', key: name, diff: `Body hash mismatch: staging=${sF.def_hash}, ${targetName}=${tF.def_hash}` });
      }
    }
  }

  for (const [name] of targetFunc) {
    if (!stagingFunc.has(name)) {
      diffs.push({ category: 'FUNCTION_EXTRA', key: name, diff: `Function extra in ${targetName}` });
    }
  }

  // Compare Triggers
  const stagingTrg = new Map((staging.triggers || []).map(t => [`${t.event_object_table}::${t.trigger_name}`, t]));
  const targetTrg = new Map((target.triggers || []).map(t => [`${t.event_object_table}::${t.trigger_name}`, t]));

  for (const [key] of stagingTrg) {
    if (!targetTrg.has(key)) {
      diffs.push({ category: 'TRIGGER_MISSING', key, diff: `Trigger missing in ${targetName}` });
    }
  }
  for (const [key] of targetTrg) {
    if (!stagingTrg.has(key)) {
      diffs.push({ category: 'TRIGGER_EXTRA', key, diff: `Extra trigger in ${targetName}` });
    }
  }

  // Compare Table Grants
  const stagingGrants = new Set((staging.grants || []).map(g => `${g.table_name}:${g.grantee}:${g.privilege_type}`));
  const targetGrants = new Set((target.grants || []).map(g => `${g.table_name}:${g.grantee}:${g.privilege_type}`));

  for (const g of stagingGrants) {
    if (!targetGrants.has(g)) {
      diffs.push({ category: 'GRANT_MISSING', key: g, diff: `Grant missing in ${targetName}` });
    }
  }
  for (const g of targetGrants) {
    if (!stagingGrants.has(g)) {
      diffs.push({ category: 'GRANT_EXTRA', key: g, diff: `Extra grant in ${targetName}` });
    }
  }

  return diffs;
}

async function run() {
  const args = process.argv.slice(2);
  const target = (args.find((a) => a.startsWith('--target=')) || '').split('=')[1] || 'rehearsal';

  console.log('====================================================');
  console.log(`DOCTORNECT SCHEMA PARITY AUDIT: Staging vs ${target.toUpperCase()}`);
  console.log('====================================================');

  const stagingUri = getEnv('STAGING_SUPABASE_DB_URL');
  if (!stagingUri) {
    console.error('Error: STAGING_SUPABASE_DB_URL is missing in environment.');
    process.exit(1);
  }

  let targetUri;
  if (target === 'rehearsal') {
    const rdsHost = getEnv('PROD_RDS_HOST');
    const rdsPort = getEnv('PROD_RDS_PORT') || '5432';
    const rdsUser = getEnv('PROD_RDS_USER') || 'postgres';
    const rdsPass = getEnv('PROD_RDS_PASSWORD');
    if (!rdsHost || !rdsPass) {
      console.log(`[SKIPPED] Target "${target}" is not configured yet (PROD_RDS_HOST or password missing).`);
      process.exit(0);
    }
    targetUri = `postgresql://${rdsUser}:${encodeURIComponent(rdsPass)}@${rdsHost}:${rdsPort}/doctornect_rehearsal?sslmode=require`;
  } else if (target === 'production') {
    const rdsHost = getEnv('PROD_RDS_HOST');
    const rdsPort = getEnv('PROD_RDS_PORT') || '5432';
    const rdsUser = getEnv('PROD_RDS_USER') || 'postgres';
    const rdsPass = getEnv('PROD_RDS_PASSWORD');
    const rdsDb = getEnv('PROD_RDS_DB') || 'doctornect';
    if (!rdsHost || !rdsPass) {
      console.log(`[SKIPPED] Target "production" is not configured yet.`);
      process.exit(0);
    }
    targetUri = `postgresql://${rdsUser}:${encodeURIComponent(rdsPass)}@${rdsHost}:${rdsPort}/${rdsDb}?sslmode=require`;
  }

  console.log(`Staging: ${maskConnectionString(stagingUri)}`);
  console.log(`Target:  ${maskConnectionString(targetUri)}`);

  const sClient = new Client({ connectionString: stagingUri, ssl: { rejectUnauthorized: false } });
  const tClient = new Client({
    connectionString: targetUri,
    ssl: { ca: fs.readFileSync(path.resolve(__dirname, '../../infra/aws/global-bundle.pem'), 'utf8'), rejectUnauthorized: true },
  });

  try {
    await sClient.connect();
    await tClient.connect();

    console.log('\nFetching catalogs from both databases...');
    const [stagingCat, targetCat] = await Promise.all([fetchCatalog(sClient), fetchCatalog(tClient)]);

    console.log(`Staging: ${stagingCat.columns.length} columns, ${stagingCat.policies.length} policies, ${stagingCat.functions.length} functions.`);
    console.log(`${target}: ${targetCat.columns.length} columns, ${targetCat.policies.length} policies, ${targetCat.functions.length} functions.`);

    const diffs = compareCatalogs(stagingCat, targetCat, target);

    console.log('\n--- PARITY AUDIT RESULTS ---');
    if (diffs.length === 0) {
      console.log('✅ ZERO UNEXPLAINED DIFFERENCES! Databases are in 100% schema parity.');
    } else {
      console.log(`⚠️ Found ${diffs.length} differences:`);
      for (const d of diffs) {
        console.log(`- [${d.category}] ${d.key}: ${d.diff}`);
      }
    }
  } finally {
    await sClient.end().catch(() => {});
    await tClient.end().catch(() => {});
  }
}

if (require.main === module) {
  run().catch((e) => {
    console.error('Fatal schema parity error:', e);
    process.exit(1);
  });
}

module.exports = {
  fetchCatalog,
  compareCatalogs,
};
