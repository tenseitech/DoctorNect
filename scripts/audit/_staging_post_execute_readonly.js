#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv } = require('../lib/env_loader');
loadRootEnv();
async function main() {
  const url = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  const client = new Client({ connectionString: String(url).replace(/^postgres:/i, 'postgresql:') });
  await client.connect();
  try {
    await client.query('BEGIN READ ONLY');
    const ledger = await client.query('SELECT count(*)::int n, max(version) head FROM public._schema_migrations');
    const carousel = await client.query(`
      SELECT count(*)::int n FROM public.promoted_ads
      WHERE status = 'active' AND payment_status = 'pending'
    `);
    const tables = [
      'prescription_medicines',
      'prescription_investigations',
      'prescription_referrals',
      'ambulance_location_updates',
    ];
    const grants = [];
    for (const t of tables) {
      const r = await client.query(
        `SELECT has_table_privilege('service_role', $1, 'INSERT') ins,
                has_table_privilege('service_role', $1, 'SELECT') sel`,
        [`public.${t}`],
      );
      grants.push({ table: t, ...r.rows[0] });
    }
    console.log(JSON.stringify({ ledger: ledger.rows[0], active_pending_ads: carousel.rows[0].n, service_role_grants: grants }));
    await client.query('ROLLBACK');
  } finally {
    await client.end();
  }
}
main().catch((e) => {
  console.error('FAIL', e.message);
  process.exit(1);
});