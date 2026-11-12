'use strict';

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { parse } = require('libpg-query');
const { getEnv } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');

async function main() {
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) {
    console.error('Missing STAGING_SUPABASE_DB_URL');
    process.exit(1);
  }

  assertDatabaseGuard({
    targetKind: 'staging',
    operationName: 'Staging Catalog Audit',
  });

  const pool = new Pool({ connectionString: dbUrl });

  console.log('Fetching live staging catalog...');
  
  // 1. Live Tables vs Views
  const liveTablesRes = await pool.query(`
    SELECT table_schema, table_name, table_type
    FROM information_schema.tables
    WHERE table_schema IN ('public', 'private')
    ORDER BY table_schema, table_type, table_name;
  `);

  // 2. Live Columns (Base Tables Only)
  const liveColsRes = await pool.query(`
    SELECT c.table_schema, c.table_name, c.column_name, c.data_type, c.is_nullable, c.column_default
    FROM information_schema.columns c
    JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
    WHERE c.table_schema IN ('public', 'private')
      AND t.table_type = 'BASE TABLE'
    ORDER BY c.table_schema, c.table_name, c.ordinal_position;
  `);

  // 3. Live Constraints
  const liveConstrRes = await pool.query(`
    SELECT tc.table_schema, tc.table_name, tc.constraint_name, tc.constraint_type,
           kcu.column_name, ccu.table_name AS foreign_table_name,
           ccu.column_name AS foreign_column_name,
           pg_get_constraintdef(c.oid) AS definition
    FROM information_schema.table_constraints tc
    JOIN pg_constraint c ON c.conname = tc.constraint_name
    LEFT JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    LEFT JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
    WHERE tc.table_schema IN ('public', 'private')
    ORDER BY tc.table_schema, tc.table_name, tc.constraint_name;
  `);

  // 4. Live Triggers
  const liveTrigRes = await pool.query(`
    SELECT trigger_schema, event_object_table AS table_name, trigger_name, action_timing,
           event_manipulation, action_statement
    FROM information_schema.triggers
    WHERE trigger_schema IN ('public', 'private')
    ORDER BY table_name, trigger_name;
  `);

  // 5. Live RLS Policies
  const livePolRes = await pool.query(`
    SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
    FROM pg_policies
    WHERE schemaname IN ('public', 'private')
    ORDER BY tablename, policyname;
  `);

  // 6. Live Functions
  const liveFuncRes = await pool.query(`
    SELECT n.nspname AS schema_name, p.proname, pg_get_function_identity_arguments(p.oid) AS args,
           p.prosecdef AS is_security_definer, p.proconfig AS search_path_config
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'private')
    ORDER BY n.nspname, p.proname, args;
  `);

  await pool.end();

  // Parse all migrations to build migration catalog
  const migrationsDir = path.resolve(__dirname, '../../db/migrations');
  const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();

  const migTables = new Map(); // tableName -> Set of columns
  const migViews = new Set();
  const migFunctions = new Set();
  const migPolicies = new Set();
  const migTriggers = new Set();

  for (const f of files) {
    const sql = fs.readFileSync(path.join(migrationsDir, f), 'utf8');
    let parsed;
    try {
      parsed = await parse(sql);
    } catch (err) {
      console.warn(`Warning parsing ${f}: ${err.message}`);
      continue;
    }

    for (const stmtObj of parsed.stmts) {
      const stmt = stmtObj.stmt;
      if (!stmt) continue;

      if (stmt.CreateStmt) {
        const tbl = stmt.CreateStmt.relation.relname.toLowerCase();
        if (!migTables.has(tbl)) migTables.set(tbl, new Set());
        if (stmt.CreateStmt.tableElts) {
          for (const elt of stmt.CreateStmt.tableElts) {
            if (elt.ColumnDef && elt.ColumnDef.colname) {
              migTables.get(tbl).add(elt.ColumnDef.colname.toLowerCase());
            }
          }
        }
      }

      if (stmt.ViewStmt) {
        const viewName = stmt.ViewStmt.view.relname.toLowerCase();
        migViews.add(viewName);
      }

      if (stmt.AlterTableStmt) {
        const tbl = stmt.AlterTableStmt.relation.relname.toLowerCase();
        if (!migTables.has(tbl)) migTables.set(tbl, new Set());
        if (stmt.AlterTableStmt.cmds) {
          for (const cmdObj of stmt.AlterTableStmt.cmds) {
            const cmd = cmdObj.AlterTableCmd;
            if (!cmd) continue;
            if (cmd.subtype === 'AT_AddColumn' || cmd.subtype === 0) {
              if (cmd.def && cmd.def.ColumnDef && cmd.def.ColumnDef.colname) {
                migTables.get(tbl).add(cmd.def.ColumnDef.colname.toLowerCase());
              }
            }
            if (cmd.subtype === 'AT_DropColumn' || cmd.subtype === 12) {
              if (cmd.name) {
                migTables.get(tbl).delete(cmd.name.toLowerCase());
              }
            }
          }
        }
      }

      if (stmt.CreateFunctionStmt) {
        const funcName = stmt.CreateFunctionStmt.funcname[stmt.CreateFunctionStmt.funcname.length - 1].String.sval.toLowerCase();
        migFunctions.add(funcName);
      }

      if (stmt.CreatePolicyStmt) {
        const polName = stmt.CreatePolicyStmt.policy_name.toLowerCase();
        const tbl = stmt.CreatePolicyStmt.table.relname.toLowerCase();
        migPolicies.add(`${tbl}.${polName}`);
      }

      if (stmt.CreateTrigStmt) {
        const trigName = stmt.CreateTrigStmt.trigname.toLowerCase();
        const tbl = stmt.CreateTrigStmt.relation.relname.toLowerCase();
        migTriggers.add(`${tbl}.${trigName}`);
      }
    }
  }

  // Regex fallback for DO blocks
  for (const f of files) {
    const sql = fs.readFileSync(path.join(migrationsDir, f), 'utf8');
    const alterRegex = /ALTER\s+TABLE(?:\s+IF\s+EXISTS)?\s+(?:public\.)?([a-zA-Z0-9_]+)\s+ADD\s+COLUMN(?:\s+IF\s+NOT\s+EXISTS)?\s+([a-zA-Z0-9_]+)/gi;
    let m;
    while ((m = alterRegex.exec(sql)) !== null) {
      const tbl = m[1].toLowerCase();
      const col = m[2].toLowerCase();
      if (!migTables.has(tbl)) migTables.set(tbl, new Set());
      migTables.get(tbl).add(col);
    }
    const createViewRegex = /CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:public\.)?([a-zA-Z0-9_]+)/gi;
    while ((m = createViewRegex.exec(sql)) !== null) {
      migViews.add(m[1].toLowerCase());
    }
  }

  const liveBaseTables = new Map();
  const liveViews = new Set();
  for (const row of liveTablesRes.rows) {
    if (row.table_type === 'BASE TABLE') {
      liveBaseTables.set(row.table_name.toLowerCase(), row);
    } else if (row.table_type === 'VIEW') {
      liveViews.add(row.table_name.toLowerCase());
    }
  }

  const liveColMap = new Map();
  for (const row of liveColsRes.rows) {
    const tbl = row.table_name.toLowerCase();
    if (!liveColMap.has(tbl)) liveColMap.set(tbl, new Map());
    liveColMap.get(tbl).set(row.column_name.toLowerCase(), row);
  }

  const tableDiffs = [];
  const colDiffs = [];

  // Exclude known views from migTables
  for (const v of migViews) {
    migTables.delete(v);
  }
  migTables.delete('doctor_directory');
  migTables.delete('patient_safe');

  for (const [tbl, cols] of migTables.entries()) {
    if (!liveBaseTables.has(tbl)) {
      tableDiffs.push({ table: tbl, status: 'MISSING_IN_STAGING' });
      continue;
    }
    const liveCols = liveColMap.get(tbl) || new Map();
    for (const c of cols) {
      if (!liveCols.has(c)) {
        colDiffs.push({ table: tbl, column: c, status: 'MISSING_IN_STAGING' });
      }
    }
    for (const [lc, details] of liveCols.entries()) {
      if (!cols.has(lc)) {
        colDiffs.push({ table: tbl, column: lc, status: 'EXTRA_IN_STAGING', details });
      }
    }
  }

  for (const [tbl] of liveBaseTables.entries()) {
    if (!migTables.has(tbl)) {
      tableDiffs.push({ table: tbl, status: 'EXTRA_IN_STAGING' });
    }
  }

  const viewDiffs = [];
  for (const v of migViews) {
    if (!liveViews.has(v)) viewDiffs.push({ view: v, status: 'MISSING_IN_STAGING' });
  }
  for (const v of liveViews) {
    if (!migViews.has(v)) viewDiffs.push({ view: v, status: 'EXTRA_IN_STAGING' });
  }

  // Exclude known views from migTables
  for (const v of migViews) {
    migTables.delete(v);
  }
  migTables.delete('doctor_directory');
  migTables.delete('patient_safe');

  console.log('\n=== PROMOTED_ADS COLUMNS ON STAGING ===');
  console.log(Array.from(liveColMap.get('promoted_ads')?.keys() || []));

  console.log('=== TABLE DIFFERENCES ===');
  console.log(JSON.stringify(tableDiffs, null, 2));

  console.log('\n=== COLUMN DIFFERENCES ===');
  console.log(JSON.stringify(colDiffs, null, 2));

  console.log('\n=== VIEW DIFFERENCES ===');
  console.log(JSON.stringify(viewDiffs, null, 2));

  // Constraints, Policies, Triggers, Functions comparisons
  const liveConstraintSet = new Set(liveConstrRes.rows.map(r => `${r.table_name}.${r.constraint_name}`.toLowerCase()));
  const livePolicySet = new Set(livePolRes.rows.map(r => `${r.tablename}.${r.policyname}`.toLowerCase()));
  const liveTriggerSet = new Set(liveTrigRes.rows.map(r => `${r.table_name}.${r.trigger_name}`.toLowerCase()));
  const liveFunctionSet = new Set(liveFuncRes.rows.map(r => r.proname.toLowerCase()));

  const trigDiffs = [];
  for (const t of migTriggers) {
    if (!liveTriggerSet.has(t)) {
      trigDiffs.push({ trigger: t, status: 'MISSING_IN_STAGING' });
    }
  }

  const polDiffs = [];
  for (const p of migPolicies) {
    if (!livePolicySet.has(p)) {
      polDiffs.push({ policy: p, status: 'MISSING_IN_STAGING' });
    }
  }

  const funcDiffs = [];
  for (const f of migFunctions) {
    if (!liveFunctionSet.has(f)) {
      funcDiffs.push({ function: f, status: 'MISSING_IN_STAGING' });
    }
  }

  console.log('\n=== TRIGGER DIFFERENCES (Pending Migrations) ===');
  console.log(JSON.stringify(trigDiffs, null, 2));

  console.log('\n=== POLICY DIFFERENCES (Pending Migrations) ===');
  console.log(JSON.stringify(polDiffs.slice(0, 10), null, 2));
  console.log(`Total policies in migrations missing in staging (pending 20261025000001): ${polDiffs.length}`);

  console.log('\n=== FUNCTION DIFFERENCES ===');
  console.log(JSON.stringify(funcDiffs, null, 2));

  const driftReport = {
    tableDiffs,
    colDiffs,
    viewDiffs,
    liveCounts: {
      baseTables: liveBaseTables.size,
      views: liveViews.size,
      columns: liveColsRes.rows.length,
      constraints: liveConstrRes.rows.length,
      triggers: liveTrigRes.rows.length,
      policies: livePolRes.rows.length,
      functions: liveFuncRes.rows.length,
    }
  };

  fs.writeFileSync('docs/ops/staging_migration_drift.json', JSON.stringify(driftReport, null, 2));
  console.log('\nReport written to docs/ops/staging_migration_drift.json');

  if (colDiffs.length > 0) {
    console.error(`\n❌ [AUDIT FAILED] Found ${colDiffs.length} column differences between migrations and staging catalog!`);
    console.error(JSON.stringify(colDiffs, null, 2));
    process.exit(1);
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
