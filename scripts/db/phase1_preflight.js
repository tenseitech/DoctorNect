'use strict';

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');

async function runPreflight() {
  const dbUrl = getEnv('PROD_SUPABASE_DB_URL') || getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) {
    console.error('FATAL: No Supabase DB URL found in environment.');
    process.exit(1);
  }

  console.log(`\n=== DoctorNect Phase 1.1 Preflight Audit ===`);
  console.log(`Target: ${maskConnectionString(dbUrl)}`);

  const pool = new Pool({ connectionString: dbUrl });
  const preflightReport = {};

  try {
    // 1. Version
    const verRes = await pool.query('SELECT version();');
    preflightReport.version = verRes.rows[0].version;
    console.log(`\n[1] PostgreSQL Version: ${preflightReport.version}`);

    // 2. Database Size
    const sizeRes = await pool.query(`SELECT pg_size_pretty(pg_database_size(current_database())) as db_size;`);
    preflightReport.dbSize = sizeRes.rows[0].db_size;
    console.log(`[2] DB Size: ${preflightReport.dbSize}`);

    // 3. Schemas
    const schemasRes = await pool.query(`
      SELECT schema_name 
      FROM information_schema.schemata 
      WHERE schema_name NOT IN ('information_schema', 'pg_catalog', 'pg_toast')
      ORDER BY schema_name;
    `);
    preflightReport.schemas = schemasRes.rows.map(r => r.schema_name);
    console.log(`[3] Schemas (${preflightReport.schemas.length}):`, preflightReport.schemas.join(', '));

    // 4. Extensions
    const extRes = await pool.query(`
      SELECT extname, extversion, extnamespace::regnamespace::text as schema
      FROM pg_extension
      ORDER BY extname;
    `);
    preflightReport.extensions = extRes.rows;
    console.log(`[4] Installed Extensions (${extRes.rows.length}):`);
    for (const e of extRes.rows) {
      console.log(`   - ${e.extname} (v${e.extversion}) in schema [${e.schema}]`);
    }

    // 5. Roles
    const rolesRes = await pool.query(`
      SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit
      FROM pg_roles
      WHERE rolname NOT LIKE 'pg_%'
      ORDER BY rolname;
    `);
    preflightReport.roles = rolesRes.rows;
    console.log(`[5] Database Roles (${rolesRes.rows.length}):`);
    for (const r of rolesRes.rows) {
      const flags = [
        r.rolsuper ? 'SUPERUSER' : null,
        r.rolcanlogin ? 'LOGIN' : 'NOLOGIN',
        r.rolbypassrls ? 'BYPASSRLS' : null,
      ].filter(Boolean).join(', ');
      console.log(`   - ${r.rolname} (${flags})`);
    }

    // 6. Publications & Tables
    const pubRes = await pool.query(`
      SELECT p.pubname, p.puballtables, t.schemaname, t.tablename
      FROM pg_publication p
      LEFT JOIN pg_publication_tables t ON p.pubname = t.pubname
      ORDER BY p.pubname, t.schemaname, t.tablename;
    `);
    const publications = {};
    for (const r of pubRes.rows) {
      if (!publications[r.pubname]) {
        publications[r.pubname] = { allTables: r.puballtables, tables: [] };
      }
      if (r.tablename) {
        publications[r.pubname].tables.push(`${r.schemaname}.${r.tablename}`);
      }
    }
    preflightReport.publications = publications;
    console.log(`[6] Publications (${Object.keys(publications).length}):`);
    for (const [name, info] of Object.entries(publications)) {
      console.log(`   - ${name} (allTables: ${info.allTables}, tables: ${info.tables.length ? info.tables.join(', ') : 'none'})`);
    }

    // 7. Cron Jobs (pg_cron)
    try {
      const cronRes = await pool.query(`SELECT jobid, schedule, command, nodename, nodeport, database, username, active FROM cron.job;`);
      preflightReport.cronJobs = cronRes.rows;
      console.log(`[7] cron.job records (${cronRes.rows.length}):`);
      for (const j of cronRes.rows) {
        console.log(`   - Job #${j.jobid} [${j.schedule}] active: ${j.active} -> ${j.command.slice(0, 60)}`);
      }
    } catch (err) {
      preflightReport.cronJobs = `Not available / error: ${err.message}`;
      console.log(`[7] cron.job: Not available or schema not present (${err.message})`);
    }

    // 8. Triggers & Functions using net.http_* (pg_net)
    const netTrigRes = await pool.query(`
      SELECT trigger_schema, trigger_name, event_object_schema, event_object_table, action_statement
      FROM information_schema.triggers
      WHERE action_statement ILIKE '%net.http%' OR action_statement ILIKE '%pg_net%'
      ORDER BY trigger_schema, trigger_name;
    `);
    const netFnRes = await pool.query(`
      SELECT n.nspname as schema_name, p.proname as function_name
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE p.prokind = 'f'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema')
        AND (pg_get_functiondef(p.oid) ILIKE '%net.http%' OR pg_get_functiondef(p.oid) ILIKE '%pg_net%')
      ORDER BY n.nspname, p.proname;
    `);
    preflightReport.netTriggers = netTrigRes.rows;
    preflightReport.netFunctions = netFnRes.rows.map(r => ({ schema: r.schema_name, function: r.function_name }));
    console.log(`[8] net.http_* Usage: Triggers: ${netTrigRes.rows.length}, Functions: ${netFnRes.rows.length}`);
    for (const f of netFnRes.rows) {
      console.log(`   - Function: ${f.schema_name}.${f.function_name}`);
    }

    // 9. Row Count Per Table across public & app schemas
    const tablesRes = await pool.query(`
      SELECT schemaname, tablename 
      FROM pg_tables 
      WHERE schemaname IN ('public', 'private')
      ORDER BY schemaname, tablename;
    `);
    const rowCounts = [];
    for (const t of tablesRes.rows) {
      try {
        const cntRes = await pool.query(`SELECT count(*)::int as cnt FROM "${t.schemaname}"."${t.tablename}";`);
        rowCounts.push({ schema: t.schemaname, table: t.tablename, count: cntRes.rows[0].cnt });
      } catch (err) {
        rowCounts.push({ schema: t.schemaname, table: t.tablename, count: -1, error: err.message });
      }
    }
    preflightReport.rowCounts = rowCounts;
    const nonEmpty = rowCounts.filter(r => r.count > 0);
    console.log(`[9] Total Tables: ${rowCounts.length} (Non-empty: ${nonEmpty.length})`);
    for (const ne of nonEmpty) {
      console.log(`   - ${ne.schema}.${ne.table}: ${ne.count} rows`);
    }

    // Save report to docs/ops/source_facts_preflight.json
    fs.writeFileSync('docs/ops/source_facts_preflight.json', JSON.stringify(preflightReport, null, 2));
    console.log(`\nPreflight facts saved to docs/ops/source_facts_preflight.json\n`);

  } finally {
    await pool.end();
  }
}

runPreflight().catch(err => {
  console.error('Preflight error:', err);
  process.exit(1);
});
