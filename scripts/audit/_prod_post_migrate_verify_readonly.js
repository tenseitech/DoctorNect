#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig } = require('../lib/rds_pool_config');
const { getEnv } = require('../lib/env_loader');

loadRootEnv();

(async () => {
  const u = getEnv('PROD_RDS_MASTER_USER');
  const pw = getEnv('PROD_RDS_MASTER_PASSWORD');
  const cfg = buildRdsPoolConfig({ user: u });
  cfg.user = u;
  cfg.password = pw;
  const client = new Client(cfg);
  await client.connect();
  const ledger = await client.query(
    `SELECT count(*)::int AS n, max(version) AS head FROM public._schema_migrations`,
  );
  const cronExt = await client.query(`SELECT extname FROM pg_extension WHERE extname = 'pg_cron'`);
  let jobNames = [];
  try {
    const jobs = await client.query(`SELECT jobname FROM cron.job ORDER BY 1`);
    jobNames = jobs.rows.map((r) => r.jobname);
  } catch (e) {
    jobNames = { error: e.code };
  }
  let anonDoctorDirectory = null;
  const dd = await client.query(`
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'doctor_directory_rows' LIMIT 1`);
  if (dd.rows[0]) {
    const sig = `public.${dd.rows[0].proname}(${dd.rows[0].args})`;
    const anonExec = await client.query(
      `SELECT has_function_privilege('anon', $1::regprocedure, 'EXECUTE') AS ok`,
      [sig],
    );
    anonDoctorDirectory = { signature: sig.replace(/public\./, ''), execute: anonExec.rows[0].ok };
  }
  const tables = [
    'prescription_medicines',
    'prescription_investigations',
    'prescription_referrals',
    'ambulance_location_updates',
    'pharmacy_delivery_medicines',
  ];
  const grants = {};
  for (const t of tables) {
    const g = await client.query(
      `SELECT has_table_privilege('authenticated', $1, 'SELECT') AS sel, has_table_privilege('service_role', $1, 'SELECT') AS sr`,
      [`public.${t}`],
    );
    grants[t] = g.rows[0];
  }
  await client.end();
  console.log(
    JSON.stringify(
      {
        ledger_rows: ledger.rows[0].n,
        ledger_head: ledger.rows[0].head,
        pg_cron_installed: Boolean(cronExt.rows[0]),
        cron_job_names: jobNames,
        anon_doctor_directory: anonDoctorDirectory,
        spot_check_grants: grants,
      },
      null,
      2,
    ),
  );
})().catch((e) => {
  console.error(e.code || '', String(e.message).slice(0, 200));
  process.exit(1);
});