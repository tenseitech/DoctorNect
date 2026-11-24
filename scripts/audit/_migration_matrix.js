#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');
const { buildRdsPoolConfig } = require('../lib/rds_pool_config');
const { listMigrationsForTarget } = require('../lib/migration_file_list');

function versionFromRel(rel) {
  return rel.split('/').pop().split('_')[0];
}

async function main() {
  const stagingFiles = listMigrationsForTarget('staging');
  const prodFiles = listMigrationsForTarget('production');
  const sc = new Client({
    connectionString: getEnv('STAGING_SUPABASE_DB_URL'),
    ssl: { rejectUnauthorized: false },
  });
  await sc.connect();
  const sr = await sc.query('SELECT version FROM public._schema_migrations');
  const stagingApplied = new Set(sr.rows.map((r) => r.version));
  await sc.end();

  const pc = new Client(buildRdsPoolConfig());
  await pc.connect();
  const pr = await pc.query('SELECT version FROM public._schema_migrations');
  const prodApplied = new Set(pr.rows.map((r) => r.version));
  await pc.end();

  const pendingStaging = stagingFiles.filter((f) => !stagingApplied.has(versionFromRel(f)));
  const pendingProd = prodFiles.filter((f) => !prodApplied.has(versionFromRel(f)));

  console.log(
    'SUMMARY',
    JSON.stringify({
      staging_repo_files: stagingFiles.length,
      prod_repo_files: prodFiles.length,
      staging_applied: stagingApplied.size,
      staging_pending: pendingStaging.length,
      prod_applied: prodApplied.size,
      prod_pending: pendingProd.length,
      rds_only_in_prod_list: prodFiles.filter((f) => f.startsWith('rds/')).length,
    }),
  );

  for (const f of prodFiles) {
    const v = versionFromRel(f);
    console.log(
      [
        v,
        f,
        stagingApplied.has(v) ? 'yes' : 'no',
        prodApplied.has(v) ? 'yes' : 'no',
        prodApplied.has(v) ? 'no' : 'yes',
        f.startsWith('rds/') ? 'yes' : 'no',
      ].join('\t'),
    );
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});