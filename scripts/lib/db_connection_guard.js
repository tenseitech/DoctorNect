'use strict';

/**
 * Supabase transaction pooler (port 6543) cannot run multi-statement transactions used by
 * migrate.js, rls_sql_harness.js, and anon_surface_audit.js. Prefer session pooler (5432) or direct DB URL.
 */

function normalizePostgresUrl(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const trimmed = raw.trim();
  if (!trimmed.includes('://')) return null;
  try {
    return new URL(trimmed.replace(/^postgres:\/\//i, 'postgresql://'));
  } catch (_) {
    return null;
  }
}

function getConnectionMeta(dbUrl) {
  const parsed = normalizePostgresUrl(dbUrl);
  if (!parsed) {
    return { port: null, hostname: '', isTransactionPooler: false, pgbouncerTransaction: false };
  }
  const port = parsed.port ? parseInt(parsed.port, 10) : 5432;
  const hostname = parsed.hostname.toLowerCase();
  const pgbouncerTransaction =
    parsed.searchParams.get('pgbouncer') === 'true' ||
    parsed.searchParams.get('pool_mode') === 'transaction';
  const isTransactionPooler = port === 6543 || pgbouncerTransaction;
  return { port, hostname, isTransactionPooler, pgbouncerTransaction };
}

function assertSessionCapableConnection(dbUrl, toolName) {
  const args = process.argv.slice(2);
  if (args.includes('--allow-transaction-pooler')) {
    console.warn(
      `[WARN] ${toolName}: --allow-transaction-pooler set; multi-statement transactions may fail on port 6543.`,
    );
    return;
  }

  const meta = getConnectionMeta(dbUrl);
  if (!meta.isTransactionPooler) return;

  console.error(`\n[CONNECTION ABORT] ${toolName} requires a session-capable Postgres URL.`);
  console.error('Detected Supabase transaction pooler (port 6543 or pgbouncer=transaction).');
  console.error('Use the session pooler on port 5432 or the direct database host URL instead.');
  console.error('Example (Supabase dashboard → Database → Connection string → Session mode):');
  console.error('  postgresql://postgres.<project-ref>:****@aws-0-..pooler.supabase.com:5432/postgres?sslmode=require');
  console.error('Set STAGING_SUPABASE_DB_URL to that value, then re-run.\n');
  process.exit(1);
}

const SESSION_CONNECTION_DOC =
  'Use STAGING_SUPABASE_DB_URL with Supabase session pooler (port 5432) or direct host — not transaction pooler (6543).';

module.exports = {
  assertSessionCapableConnection,
  getConnectionMeta,
  SESSION_CONNECTION_DOC,
};
