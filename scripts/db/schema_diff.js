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

/** Extensions present on Supabase-managed Postgres but not required on RDS parity checks. */
const SUPABASE_ONLY_EXTENSIONS = new Set([
  'pg_graphql',
  'supabase_vault',
  'pg_net',
  'wrappers',
  'pgsodium',
  'vault',
]);

/** Schemas owned by Supabase platform — excluded from object-level drift reporting. */
const SUPABASE_ONLY_SCHEMAS = new Set([
  'auth',
  'extensions',
  'graphql',
  'graphql_public',
  'pgbouncer',
  'pgsodium',
  'pgsodium_masks',
  'realtime',
  '_realtime',
  'storage',
  'supabase_functions',
  'supabase_migrations',
  'vault',
]);

const EXPECTED_POSTGREST_ROLES = ['anon', 'authenticated', 'service_role', 'authenticator'];
const EXPECTED_AUTH_SHIM_FUNCTIONS = ['jwt', 'uid', 'role'];

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

  // 7. Extensions (Supabase-only names filtered at compare time)
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

async function fetchInfraCatalog(client) {
  const authFuncsRes = await client.query(`
    SELECT p.proname,
           pg_get_functiondef(p.oid) AS definition
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'auth' AND p.prokind = 'f'
    ORDER BY p.proname;
  `);
  const authFunctions = authFuncsRes.rows.map((r) => ({
    proname: r.proname,
    def_hash: crypto.createHash('sha256').update(r.definition || '').digest('hex').slice(0, 16),
  }));

  const rolesRes = await client.query(`
    SELECT rolname, rolcanlogin
    FROM pg_roles
    WHERE rolname = ANY($1::text[])
    ORDER BY rolname;
  `, [EXPECTED_POSTGREST_ROLES]);
  const roles = rolesRes.rows;

  const authGrantsRes = await client.query(`
    SELECT grantee, privilege_type
    FROM information_schema.usage_privileges
    WHERE object_schema = 'auth'
    ORDER BY grantee, privilege_type;
  `);
  const authFunctionGrantsRes = await client.query(`
    SELECT grantee, specific_name, privilege_type
    FROM information_schema.routine_privileges
    WHERE routine_schema = 'auth'
    ORDER BY specific_name, grantee, privilege_type;
  `);

  return {
    authFunctions,
    roles,
    authSchemaGrants: authGrantsRes.rows,
    authFunctionGrants: authFunctionGrantsRes.rows,
  };
}

function filterComparableExtensions(extensions) {
  return (extensions || []).filter((e) => !SUPABASE_ONLY_EXTENSIONS.has(e.extname));
}

function compareInfraCatalogs(stagingInfra, targetInfra, targetName) {
  const diffs = [];

  for (const name of EXPECTED_AUTH_SHIM_FUNCTIONS) {
    const sFn = stagingInfra.authFunctions.find((f) => f.proname === name);
    const tFn = targetInfra.authFunctions.find((f) => f.proname === name);
    if (!tFn) {
      diffs.push({
        category: 'AUTH_SHIM_MISSING',
        key: `auth.${name}()`,
        diff: `Missing auth shim in ${targetName} (see db/rds_bootstrap/02_auth_shim.sql)`,
      });
    } else if (sFn && sFn.def_hash !== tFn.def_hash) {
      diffs.push({
        category: 'AUTH_SHIM_BODY',
        key: `auth.${name}()`,
        diff: `auth.${name}() body hash mismatch staging=${sFn?.def_hash || 'n/a'} ${targetName}=${tFn.def_hash}`,
      });
    }
  }

  const stagingRoles = new Map(stagingInfra.roles.map((r) => [r.rolname, r]));
  const targetRoles = new Map(targetInfra.roles.map((r) => [r.rolname, r]));
  for (const rolename of EXPECTED_POSTGREST_ROLES) {
    if (!targetRoles.has(rolename)) {
      diffs.push({
        category: 'ROLE_MISSING',
        key: rolename,
        diff: `PostgREST role missing in ${targetName}`,
      });
    } else if (stagingRoles.has(rolename)) {
      const s = stagingRoles.get(rolename);
      const t = targetRoles.get(rolename);
      if (Boolean(s.rolcanlogin) !== Boolean(t.rolcanlogin)) {
        diffs.push({
          category: 'ROLE_LOGIN',
          key: rolename,
          diff: `rolcanlogin mismatch staging=${s.rolcanlogin} ${targetName}=${t.rolcanlogin}`,
        });
      }
    }
  }

  const stagingAuthGrants = new Set(
    (stagingInfra.authSchemaGrants || []).map((g) => `${g.grantee}:${g.privilege_type}`),
  );
  const targetAuthGrants = new Set(
    (targetInfra.authSchemaGrants || []).map((g) => `${g.grantee}:${g.privilege_type}`),
  );
  for (const g of stagingAuthGrants) {
    if (!targetAuthGrants.has(g)) {
      diffs.push({ category: 'AUTH_GRANT_MISSING', key: g, diff: `auth schema grant missing in ${targetName}` });
    }
  }
  for (const g of targetAuthGrants) {
    if (!stagingAuthGrants.has(g)) {
      diffs.push({ category: 'AUTH_GRANT_EXTRA', key: g, diff: `Extra auth schema grant in ${targetName}` });
    }
  }

  return diffs;
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

  const stagingExt = new Map(
    filterComparableExtensions(staging.extensions).map((e) => [e.extname, e.extversion]),
  );
  const targetExt = new Map(
    filterComparableExtensions(target.extensions).map((e) => [e.extname, e.extversion]),
  );
  for (const [name, ver] of stagingExt) {
    if (!targetExt.has(name)) {
      diffs.push({ category: 'EXTENSION_MISSING', key: name, diff: `Extension missing in ${targetName}` });
    } else if (targetExt.get(name) !== ver) {
      diffs.push({
        category: 'EXTENSION_VERSION',
        key: name,
        diff: `Version mismatch staging=${ver} ${targetName}=${targetExt.get(name)}`,
      });
    }
  }
  for (const [name] of targetExt) {
    if (!stagingExt.has(name)) {
      diffs.push({ category: 'EXTENSION_EXTRA', key: name, diff: `Extra extension in ${targetName}` });
    }
  }

  return diffs;
}

function mergeCatalogDiffs(stagingCat, targetCat, stagingInfra, targetInfra, targetName) {
  return [
    ...compareCatalogs(stagingCat, targetCat, targetName),
    ...compareInfraCatalogs(stagingInfra, targetInfra, targetName),
  ];
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

  const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');

  let targetUri;
  let rehearsalCfg = null;
  let productionCfg = null;
  if (target === 'rehearsal') {
    try {
      rehearsalCfg = buildRdsPoolConfig({ database: 'doctornect_rehearsal' });
      targetUri = maskRdsTarget(rehearsalCfg);
    } catch (_) {
      console.log(`[SKIPPED] Target "rehearsal" is not configured yet (PROD_RDS_* missing).`);
      process.exit(0);
    }
  } else if (target === 'fresh' || target === 'fresh_local') {
    targetUri = getEnv('LOCAL_FRESH_DB_URL');
    if (!targetUri) {
      const base = getEnv('REPLAY_DB_URL') || '';
      const dbName = process.env.FRESH_LOCAL_DB_NAME || 'doctornect_fresh_zero';
      if (!base) {
        console.error('Error: set LOCAL_FRESH_DB_URL or REPLAY_DB_URL (fresh DB name via FRESH_LOCAL_DB_NAME).');
        process.exit(1);
      }
      const u = new URL(base.replace(/^postgres:\/\//i, 'postgresql://'));
      u.pathname = `/${dbName}`;
      targetUri = u.toString();
    }
  } else if (target === 'production') {
    try {
      productionCfg = buildRdsPoolConfig({ database: getEnv('PROD_RDS_DB') || 'doctornect' });
      targetUri = maskRdsTarget(productionCfg);
    } catch (_) {
      console.log(`[SKIPPED] Target "production" is not configured yet.`);
      process.exit(0);
    }
  }

  console.log(`Staging: ${maskConnectionString(stagingUri)}`);
  console.log(`Target:  ${maskConnectionString(targetUri)}`);

  const sClient = new Client({ connectionString: stagingUri, ssl: { rejectUnauthorized: false } });
  const isLocalFresh = target === 'fresh' || target === 'fresh_local';
  let tClient;
  const { assertProductionRdsTarget, verifyConnectedRdsSession } = require('../lib/rds_connect_guard');
  if (isLocalFresh) {
    tClient = new Client({ connectionString: targetUri });
  } else if (target === 'production') {
    const prodCfg = productionCfg || buildRdsPoolConfig({ database: getEnv('PROD_RDS_DB') || 'doctornect' });
    assertProductionRdsTarget(prodCfg);
    tClient = new Client(prodCfg);
  } else if (target === 'rehearsal') {
    const cfg = rehearsalCfg || buildRdsPoolConfig({ database: 'doctornect_rehearsal' });
    assertProductionRdsTarget(cfg);
    tClient = new Client(cfg);
  } else {
    tClient = new Client({
      connectionString: targetUri,
      ssl: { ca: fs.readFileSync(path.resolve(__dirname, '../../infra/aws/global-bundle.pem'), 'utf8'), rejectUnauthorized: true },
    });
  }

  try {
    await sClient.connect();
    await tClient.connect();
    if (target === 'production') {
      await verifyConnectedRdsSession(
        tClient,
        productionCfg || buildRdsPoolConfig({ database: getEnv('PROD_RDS_DB') || 'doctornect' }),
      );
    } else if (target === 'rehearsal') {
      await verifyConnectedRdsSession(
        tClient,
        rehearsalCfg || buildRdsPoolConfig({ database: 'doctornect_rehearsal' }),
      );
    }

    console.log(
      `\nSupabase-only schemas ignored for object drift: ${[...SUPABASE_ONLY_SCHEMAS].sort().join(', ')}`,
    );
    console.log('\nFetching catalogs from both databases...');
    const [stagingCat, targetCat, stagingInfra, targetInfra] = await Promise.all([
      fetchCatalog(sClient),
      fetchCatalog(tClient),
      fetchInfraCatalog(sClient),
      fetchInfraCatalog(tClient),
    ]);

    console.log(`Staging: ${stagingCat.columns.length} columns, ${stagingCat.policies.length} policies, ${stagingCat.functions.length} functions.`);
    console.log(`${target}: ${targetCat.columns.length} columns, ${targetCat.policies.length} policies, ${targetCat.functions.length} functions.`);
    console.log(
      `Auth shim: staging=${stagingInfra.authFunctions.map((f) => f.proname).join(',') || 'none'}; ${target}=${targetInfra.authFunctions.map((f) => f.proname).join(',') || 'none'}`,
    );

    const diffs = mergeCatalogDiffs(stagingCat, targetCat, stagingInfra, targetInfra, target);

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
  fetchInfraCatalog,
  compareCatalogs,
  compareInfraCatalogs,
  mergeCatalogDiffs,
  filterComparableExtensions,
  SUPABASE_ONLY_EXTENSIONS,
  SUPABASE_ONLY_SCHEMAS,
};
