'use strict';

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { getEnv, maskConnectionString, printEnvSummary } = require('../lib/env_loader');

async function testRdsPreflight() {
  const host = getEnv('PROD_RDS_HOST');
  const port = parseInt(getEnv('PROD_RDS_PORT') || '5432', 10);
  const database = getEnv('PROD_RDS_DB') || 'postgres';
  const user = getEnv('PROD_RDS_USER') || 'postgres';
  const password = getEnv('PROD_RDS_PASSWORD');
  const certPath = getEnv('PROD_RDS_SSL_ROOT_CERT') || path.resolve(__dirname, '../../infra/aws/global-bundle.pem');

  if (!host || !password) {
    console.log('\n[BLOCKED] RDS Preflight cannot connect: PROD_RDS_HOST or PROD_RDS_PASSWORD not set.');
    console.log('Action needed: User must provision RDS PostgreSQL instance and populate credentials.');
    return { blocked: true, reason: 'Credentials missing in environment' };
  }

  if (!fs.existsSync(certPath)) {
    console.error(`\n[FATAL] AWS RDS CA Certificate not found at: ${certPath}`);
    process.exit(1);
  }

  console.log(`\nConnecting to RDS PostgreSQL at ${host}:${port}/${database} as ${user} with strict TLS verification...`);
  const ca = fs.readFileSync(certPath);

  const pool = new Pool({
    host,
    port,
    database,
    user,
    password,
    ssl: {
      rejectUnauthorized: true,
      ca,
    },
  });

  const report = {};

  try {
    const verRes = await pool.query('SELECT version();');
    report.version = verRes.rows[0].version;
    console.log('RDS Engine Version:', report.version);

    const sslRes = await pool.query("SHOW rds.force_ssl;");
    report.forceSsl = sslRes.rows[0].rds_force_ssl;
    console.log('rds.force_ssl:', report.forceSsl);

    const connRes = await pool.query("SHOW max_connections;");
    report.maxConnections = connRes.rows[0].max_connections;
    console.log('max_connections:', report.maxConnections);

    const userRes = await pool.query("SELECT current_user, session_user;");
    report.currentUser = userRes.rows[0];
    console.log('Current User:', report.currentUser);

    const superuserRes = await pool.query(`
      SELECT pg_has_role(current_user, 'rds_superuser', 'MEMBER') as is_rds_superuser;
    `);
    report.isRdsSuperuser = superuserRes.rows[0].is_rds_superuser;
    console.log('rds_superuser membership:', report.isRdsSuperuser);

    // Test BYPASSRLS capability
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

    const encRes = await pool.query(`
      SELECT datname, pg_encoding_to_char(encoding) as encoding, datcollate, datctype
      FROM pg_database WHERE datname = current_database();
    `);
    report.encoding = encRes.rows[0];
    console.log('Database Encoding/Collation:', report.encoding);

    const tzRes = await pool.query("SHOW timezone;");
    report.timezone = tzRes.rows[0].TimeZone;
    console.log('Timezone:', report.timezone);

    const extRes = await pool.query("SELECT name, default_version, installed_version FROM pg_available_extensions ORDER BY name;");
    report.availableExtensions = extRes.rows;
    console.log(`Available Extensions in RDS: ${extRes.rows.length}`);

    fs.writeFileSync('docs/ops/rds_preflight_report.json', JSON.stringify(report, null, 2));
    console.log('\nRDS Preflight passed! Saved to docs/ops/rds_preflight_report.json');
    return { blocked: false, report };

  } catch (err) {
    console.error('\nRDS Connection Failed:', err.message);
    let likelyCause = 'Unknown';
    if (err.message.includes('ETIMEDOUT') || err.message.includes('ENOTFOUND')) {
      likelyCause = 'Network timeout / Security group not allowing inbound port 5432 from caller IP, or host not publicly accessible.';
    } else if (err.message.includes('SELF_SIGNED_CERT_IN_CHAIN') || err.message.includes('unable to verify the first certificate')) {
      likelyCause = 'CA Bundle mismatch or TLS handshake verification failure.';
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
