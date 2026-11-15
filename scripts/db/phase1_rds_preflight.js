'use strict';

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');

async function testRdsPreflight() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });

  let poolConfig;
  try {
    poolConfig = buildRdsPoolConfig();
  } catch (err) {
    console.log(`\n[BLOCKED] RDS Preflight cannot connect: ${err.message}`);
    console.log('Action needed: set PROD_RDS_HOST, PROD_RDS_PASSWORD, PROD_RDS_PORT, PROD_RDS_DB in root .env.');
    return { blocked: true, reason: err.message };
  }

  const database = poolConfig.database;
  const user = poolConfig.user;
  console.log(`\nConnecting (masked): ${maskRdsTarget(poolConfig)}`);
  console.log(`Target database name: ${database}`);
  console.log(`Target database user: ${user}`);

  const pool = new Pool(poolConfig);
  const report = { database, user };

  try {
    const verRes = await pool.query('SELECT version();');
    report.version = verRes.rows[0].version;
    console.log('RDS Engine Version:', report.version);

    const sslRes = await pool.query('SHOW rds.force_ssl;');
    report.forceSsl = sslRes.rows[0].rds_force_ssl;
    console.log('rds.force_ssl:', report.forceSsl);

    const connRes = await pool.query('SHOW max_connections;');
    report.maxConnections = connRes.rows[0].max_connections;
    console.log('max_connections:', report.maxConnections);

    const userRes = await pool.query('SELECT current_user, session_user, current_database();');
    report.currentUser = userRes.rows[0];
    console.log('Session:', report.currentUser);

    const superuserRes = await pool.query(`
      SELECT pg_has_role(current_user, 'rds_superuser', 'MEMBER') as is_rds_superuser;
    `);
    report.isRdsSuperuser = superuserRes.rows[0].is_rds_superuser;
    console.log('rds_superuser membership:', report.isRdsSuperuser);

    try {
      await pool.query(`
        DO $$
        BEGIN
          CREATE ROLE __test_rls_bypass_check WITH NOLOGIN BYPASSRLS;
          DROP ROLE __test_rls_bypass_check;
        END $$;
      `);
      report.bypassRlsPermitted = true;
      console.log('CREATE ROLE ... BYPASSRLS permitted: YES');
    } catch (err) {
      report.bypassRlsPermitted = false;
      report.bypassRlsError = err.message;
      console.log('CREATE ROLE ... BYPASSRLS permitted: NO (' + err.message + ')');
    }

    const tableCount = await pool.query(
      `SELECT count(*)::int AS n FROM pg_class c
       JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','auth','private') AND c.relkind = 'r'`,
    );
    report.app_schema_table_count = tableCount.rows[0].n;
    console.log(`App-schema tables (public+auth+private) in "${database}": ${report.app_schema_table_count}`);

    const encRes = await pool.query(`
      SELECT datname, pg_encoding_to_char(encoding) as encoding, datcollate, datctype
      FROM pg_database WHERE datname = current_database();
    `);
    report.encoding = encRes.rows[0];
    console.log('Database Encoding/Collation:', report.encoding);

    const tzRes = await pool.query('SHOW timezone;');
    report.timezone = tzRes.rows[0].TimeZone;
    console.log('Timezone:', report.timezone);

    const extRes = await pool.query(
      'SELECT name, default_version, installed_version FROM pg_available_extensions ORDER BY name;',
    );
    report.availableExtensions = extRes.rows;
    console.log(`Available Extensions in RDS: ${extRes.rows.length}`);

    fs.writeFileSync(
      path.resolve(__dirname, '../../docs/ops/rds_preflight_report.json'),
      JSON.stringify(report, null, 2),
    );
    console.log('\nRDS Preflight passed! Saved to docs/ops/rds_preflight_report.json');
    return { blocked: false, report };
  } catch (err) {
    console.error('\nRDS Connection Failed:', err.message);
    let likelyCause = 'Unknown';
    if (err.message.includes('ETIMEDOUT') || err.message.includes('ENOTFOUND')) {
      likelyCause = 'Network timeout / Security group or tunnel.';
    } else if (err.message.includes('SELF_SIGNED_CERT_IN_CHAIN') || err.message.includes('unable to verify')) {
      likelyCause = 'CA Bundle mismatch or TLS handshake failure.';
    } else if (err.message.includes('password authentication failed')) {
      likelyCause = 'Incorrect username or password.';
    }
    return { blocked: true, error: err.message, likelyCause };
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  testRdsPreflight().catch(console.error);
}

module.exports = { testRdsPreflight };