'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');

async function exportCatalogAndArtifacts() {
  const dbUrl = getEnv('PROD_SUPABASE_DB_URL') || getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) {
    console.error('FATAL: No Supabase DB URL found in environment.');
    process.exit(1);
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupDir = path.resolve('backups', `supabase_${timestamp}`);
  if (!fs.existsSync(backupDir)) {
    fs.mkdirSync(backupDir, { recursive: true });
  }

  console.log(`\n=== DoctorNect Phase 2 Backup Artifacts Generation ===`);
  console.log(`Target: ${maskConnectionString(dbUrl)}`);
  console.log(`Output Directory: ${backupDir}`);

  const pool = new Pool({ connectionString: dbUrl });
  const catalog = {};

  try {
    // 1. Roles
    const roles = await pool.query(`SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls FROM pg_roles ORDER BY rolname;`);
    catalog.roles = roles.rows;

    // 2. Table ACLs & RLS Flags
    const tables = await pool.query(`
      SELECT c.oid, n.nspname as schema, c.relname as table_name, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced, c.relacl as acl
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname IN ('public', 'private') AND c.relkind = 'r'
      ORDER BY n.nspname, c.relname;
    `);
    catalog.tables = tables.rows;

    // 3. RLS Policies (qual & with_check)
    const policies = await pool.query(`
      SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
      FROM pg_policies
      WHERE schemaname IN ('public', 'private')
      ORDER BY schemaname, tablename, policyname;
    `);
    catalog.policies = policies.rows;

    // 4. Views & security_invoker
    const views = await pool.query(`
      SELECT n.nspname as schema, c.relname as view_name, c.reloptions, pg_get_viewdef(c.oid) as definition
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname IN ('public', 'private') AND c.relkind = 'v'
      ORDER BY n.nspname, c.relname;
    `);
    catalog.views = views.rows.map(v => ({
      schema: v.schema,
      name: v.view_name,
      security_invoker: (v.reloptions || []).some(o => o.includes('security_invoker=true')),
      reloptions: v.reloptions,
      definition: v.definition
    }));

    // 5. Functions (SECURITY DEFINER, proconfig, ACL)
    const functions = await pool.query(`
      SELECT n.nspname as schema, p.proname as function_name, pg_get_function_identity_arguments(p.oid) as args,
             p.prosecdef as is_security_definer, p.proconfig, p.proacl as acl,
             r.rolname as owner, pg_get_functiondef(p.oid) as definition
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_roles r ON r.oid = p.proowner
      WHERE n.nspname IN ('public', 'private') AND p.prokind = 'f'
      ORDER BY n.nspname, p.proname;
    `);
    catalog.functions = functions.rows;

    // 6. Triggers
    const triggers = await pool.query(`
      SELECT trigger_schema, trigger_name, event_object_schema, event_object_table,
             action_order, action_condition, action_statement, action_orientation, action_timing
      FROM information_schema.triggers
      WHERE event_object_schema IN ('public', 'private')
      ORDER BY event_object_schema, event_object_table, trigger_name;
    `);
    catalog.triggers = triggers.rows;

    // 7. Event Triggers
    const eventTriggers = await pool.query(`SELECT evtname, evtevent, evtowner::regrole::text as owner, evtfoid::regproc::text as function FROM pg_event_trigger;`);
    catalog.eventTriggers = eventTriggers.rows;

    // 8. Publications
    const pubRes = await pool.query(`
      SELECT p.pubname, p.puballtables, t.schemaname, t.tablename
      FROM pg_publication p
      LEFT JOIN pg_publication_tables t ON p.pubname = t.pubname
      ORDER BY p.pubname, t.schemaname, t.tablename;
    `);
    catalog.publications = pubRes.rows;

    // 9. Extensions
    const extRes = await pool.query(`SELECT extname, extversion, extnamespace::regnamespace::text as schema FROM pg_extension ORDER BY extname;`);
    catalog.extensions = extRes.rows;

    // 10. Cron Jobs
    try {
      const cronRes = await pool.query(`SELECT jobid, schedule, command, nodename, nodeport, database, username, active FROM cron.job;`);
      catalog.cronJobs = cronRes.rows;
    } catch (_) {
      catalog.cronJobs = [];
    }

    // 11. Sequences
    const seqRes = await pool.query(`SELECT sequence_schema, sequence_name, data_type FROM information_schema.sequences WHERE sequence_schema IN ('public', 'private');`);
    catalog.sequences = seqRes.rows;

    // 12. Enums
    const enumRes = await pool.query(`
      SELECT n.nspname as schema, t.typname as enum_name, e.enumlabel
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE n.nspname IN ('public', 'private')
      ORDER BY n.nspname, t.typname, e.enumsortorder;
    `);
    catalog.enums = enumRes.rows;

    // 13. Constraints & Indexes
    const constraints = await pool.query(`
      SELECT conname, contype, conrelid::regclass::text as table_name, pg_get_constraintdef(oid) as definition
      FROM pg_constraint
      WHERE connamespace IN (SELECT oid FROM pg_namespace WHERE nspname IN ('public', 'private'))
      ORDER BY conname;
    `);
    catalog.constraints = constraints.rows;

    const indexes = await pool.query(`
      SELECT schemaname, tablename, indexname, indexdef
      FROM pg_indexes
      WHERE schemaname IN ('public', 'private')
      ORDER BY schemaname, tablename, indexname;
    `);
    catalog.indexes = indexes.rows;

    // 14. pg_default_acl
    const defaultAcl = await pool.query(`SELECT defaclrole::regrole::text as role, defaclnamespace::regnamespace::text as schema, defaclobjtype, defaclacl FROM pg_default_acl;`);
    catalog.defaultAcl = defaultAcl.rows;

    // Write catalog_exports.json
    fs.writeFileSync(path.join(backupDir, 'catalog_exports.json'), JSON.stringify(catalog, null, 2));
    console.log(`[PASS] catalog_exports.json created (${(fs.statSync(path.join(backupDir, 'catalog_exports.json')).size / 1024).toFixed(1)} KB)`);

    // 15. migrations_ledger.json
    let appliedMigrations = [];
    try {
      const migRes = await pool.query(`SELECT * FROM supabase_migrations.schema_migrations ORDER BY version;`);
      appliedMigrations = migRes.rows;
    } catch (err) {
      console.warn('Could not query supabase_migrations.schema_migrations:', err.message);
    }

    const localMigrationsDir = path.resolve('db/migrations');
    const localFiles = fs.readdirSync(localMigrationsDir).filter(f => f.endsWith('.sql')).sort();
    const localMigrations = localFiles.map(f => {
      const content = fs.readFileSync(path.join(localMigrationsDir, f));
      const hash = crypto.createHash('sha256').update(content).digest('hex');
      return { file: f, sha256: hash };
    });

    let gitHead = '';
    try {
      gitHead = execSync('git rev-parse HEAD', { encoding: 'utf8' }).trim();
    } catch (_) {
      gitHead = 'unknown';
    }

    const migrationsLedger = {
      gitHead,
      appliedInDatabase: appliedMigrations,
      localMigrationFiles: localMigrations,
    };
    fs.writeFileSync(path.join(backupDir, 'migrations_ledger.json'), JSON.stringify(migrationsLedger, null, 2));
    console.log(`[PASS] migrations_ledger.json created (${localMigrations.length} local migrations tracked)`);

    // 16. table_classification.md
    let tableMd = `# DoctorNect Table Classification & Production Seed Policy\n\n`;
    tableMd += `**Rule:** Default: only reference data and app config are copied to production. Everything ambiguous defaults to NOT copied.\n\n`;
    tableMd += `| Table Name | Category | Current Row Count | Copy to Production? | Rationale |\n`;
    tableMd += `|---|---|---|---|---|\n`;

    const tablesList = tables.rows;
    for (const t of tablesList) {
      let count = 0;
      try {
        const cRes = await pool.query(`SELECT count(*)::int as cnt FROM "${t.schema}"."${t.table_name}";`);
        count = cRes.rows[0].cnt;
      } catch (_) {}

      let category = 'User-generated';
      let copy = 'NO';
      let rationale = 'Production starts empty for live user registrations.';

      if (t.table_name === 'system_config' || t.table_name === 'banner_configs') {
        category = 'App config';
        copy = 'YES';
        rationale = 'Essential baseline application configuration.';
      } else if (t.table_name === 'abuse_rate_limits' || t.table_name === 'otp_challenges' || t.table_name === 'storage_audit_logs') {
        category = 'Log / Ephemeral Queue';
        copy = 'NO';
        rationale = 'Transient runtime rate limits and challenge tokens.';
      } else if (t.table_name.startsWith('test_') || t.table_name.includes('mock')) {
        category = 'Test-only';
        copy = 'NO';
        rationale = 'Test fixture.';
      } else if (t.table_name === 'medical_specializations' || t.table_name === 'lab_catalog_tests') {
        category = 'Reference data';
        copy = 'YES';
        rationale = 'Static master catalog data.';
      } else if (t.table_name === 'doctors' || t.table_name === 'medical_stores') {
        category = 'Staging Seed / Demo Providers';
        copy = 'NO';
        rationale = 'Test/demo accounts on staging. Real providers must register in production.';
      }

      tableMd += `| \`${t.schema}.${t.table_name}\` | ${category} | ${count} | **${copy}** | ${rationale} |\n`;
    }
    fs.writeFileSync(path.join(backupDir, 'table_classification.md'), tableMd);
    console.log(`[PASS] table_classification.md created (${tablesList.length} tables categorized)`);

    // 17. dashboard_config_checklist.md
    let dashMd = `# Supabase Dashboard Configuration Checklist (Form with Blanks)\n\n`;
    dashMd += `**Project:** \`rnltknemwnjrjxthtull\` (Staging)  \n`;
    dashMd += `*Fill in from Supabase Web Dashboard settings to capture non-SQL configurations.*\n\n`;
    dashMd += `## 1. Authentication & Third-Party Auth\n`;
    dashMd += `- Third-Party Auth Provider: [ ] Enabled (Firebase Auth)\n`;
    dashMd += `- Firebase Project ID: \`medibond-45fad\`\n`;
    dashMd += `- JWT Secret (masked): ________________________\n`;
    dashMd += `- JWT Expiry (seconds): ________________________\n`;
    dashMd += `- External Providers Enabled: ________________________\n\n`;
    dashMd += `## 2. API & PostgREST Settings\n`;
    dashMd += `- Exposed Schemas: \`public\`\n`;
    dashMd += `- Extra Search Path: \`public, extensions\`\n`;
    dashMd += `- Max Rows Returned: ________________________\n`;
    dashMd += `- Statement Timeout (ms): ________________________\n\n`;
    dashMd += `## 3. Realtime Settings\n`;
    dashMd += `- Realtime Enabled: [ ] Yes\n`;
    dashMd += `- Max Concurrent Clients: ________________________\n`;
    dashMd += `- Max Messages Per Second: ________________________\n\n`;
    dashMd += `## 4. Database Webhooks & Triggers\n`;
    dashMd += `- Webhooks configured in dashboard: [ ] None / List: ____________________\n\n`;
    dashMd += `## 5. Network Restrictions & Pooler\n`;
    dashMd += `- Allowed CIDRs / IP Restrictions: ________________________\n`;
    dashMd += `- Pooler Mode: Transaction (Port 6543) / Session (Port 5432)\n`;
    dashMd += `- Pool Size: ________________________\n`;
    fs.writeFileSync(path.join(backupDir, 'dashboard_config_checklist.md'), dashMd);
    console.log(`[PASS] dashboard_config_checklist.md created`);

    // 18. MANIFEST.md draft
    let manifestMd = `# DoctorNect Supabase Backup Manifest\n\n`;
    manifestMd += `- **Timestamp (UTC):** ${new Date().toISOString()}\n`;
    manifestMd += `- **Source Database:** \`rnltknemwnjrjxthtull\` (PostgreSQL 17.11)\n`;
    manifestMd += `- **Git Commit:** \`${gitHead}\`\n`;
    manifestMd += `- **Catalog Export:** \`catalog_exports.json\` (${(fs.statSync(path.join(backupDir, 'catalog_exports.json')).size / 1024).toFixed(1)} KB)\n`;
    manifestMd += `- **Migrations Ledger:** \`migrations_ledger.json\` (${localMigrations.length} files)\n`;
    manifestMd += `- **Table Classification:** \`table_classification.md\` (${tablesList.length} tables)\n`;
    manifestMd += `- **Dashboard Checklist:** \`dashboard_config_checklist.md\`\n`;
    manifestMd += `- **SQL Dumps Status:** PENDING NATIVE PG_DUMP INSTALLATION (See MANUAL_ACTIONS.md Item 1)\n`;
    fs.writeFileSync(path.join(backupDir, 'MANIFEST.md'), manifestMd);
    console.log(`[PASS] MANIFEST.md created in ${backupDir}`);

    return { backupDir, timestamp };

  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  exportCatalogAndArtifacts().catch(console.error);
}

module.exports = { exportCatalogAndArtifacts };
