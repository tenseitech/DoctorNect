#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig } = require('../lib/rds_pool_config');
const { getEnv } = require('../lib/env_loader');

loadRootEnv();

const TABLES = [
  { table: 'users', idCol: 'id', extra: `OR email ILIKE '%@test.local' OR id ILIKE 'authz_%'` },
  { table: 'doctors', idCol: 'id' },
  { table: 'patients', idCol: 'id' },
  { table: 'medical_stores', idCol: 'id' },
  { table: 'labs', idCol: 'id' },
  { table: 'ambulances', idCol: 'id' },
  { table: 'appointments', idCol: 'id' },
  { table: 'promoted_ads', idCol: 'id' },
  { table: 'prescriptions', idCol: 'id' },
  { table: 'prescription_medicines', idCol: 'id' },
  { table: 'prescription_investigations', idCol: 'id' },
  { table: 'prescription_referrals', idCol: 'id' },
  { table: 'admin_users', idCol: 'id' },
  { table: 'support_tickets', idCol: 'id' },
  { table: 'notification_outbox', idCol: 'id' },
];

const PAT = `(id LIKE 'test\\_%' ESCAPE '\\' OR id LIKE 'harness\\_%' ESCAPE '\\' OR id LIKE 'authz\\_%' ESCAPE '\\')`;

async function countsFor(client, label) {
  const out = { env: label, tables: {}, totals: 0 };
  for (const { table, extra } of TABLES) {
    const where = extra ? `WHERE ${PAT} ${extra}` : `WHERE ${PAT}`;
    const sql = `SELECT count(*)::int AS n FROM public.${table} ${where}`;
    try {
      const r = await client.query(sql);
      const n = r.rows[0].n;
      if (n > 0) out.tables[table] = n;
      out.totals += n;
    } catch (e) {
      if (e.code === '42P01') out.tables[table] = { missing: true };
      else out.tables[table] = { error: e.code };
    }
  }
  const totalRows = await client.query(`
    SELECT relname AS table, n_live_tup::bigint AS approx
    FROM pg_stat_user_tables
    WHERE schemaname = 'public'
      AND relname = ANY($1::text[])
    ORDER BY 1`,
    [TABLES.map((t) => t.table)],
  );
  out.approx_row_counts = Object.fromEntries(
    totalRows.rows.map((r) => [r.table, Number(r.approx)]),
  );
  return out;
}

(async () => {
  const prodCfg = buildRdsPoolConfig({ user: getEnv('PROD_RDS_MASTER_USER') });
  prodCfg.user = getEnv('PROD_RDS_MASTER_USER');
  prodCfg.password = getEnv('PROD_RDS_MASTER_PASSWORD');
  const prod = new Client(prodCfg);
  await prod.connect();
  const prodCounts = await countsFor(prod, 'production');
  await prod.end();

  let stagingCounts = { env: 'staging', skipped: true, reason: 'STAGING_SUPABASE_DB_URL unset' };
  const stagingUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  if (stagingUrl) {
    const st = new Client({ connectionString: stagingUrl });
    await st.connect();
    stagingCounts = await countsFor(st, 'staging');
    await st.end();
  }

  console.log(JSON.stringify({ harness_pattern_residue: prodCounts, staging_compare: stagingCounts }, null, 2));
})().catch((e) => {
  console.error(e.code || '', e.message);
  process.exit(1);
});