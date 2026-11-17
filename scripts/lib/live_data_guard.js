'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { getEnv } = require('./env_loader');
const { getHostFingerprint } = require('./env_guard');

const ALLOWLIST_PATH = path.resolve(__dirname, '../../docs/audit/allowed_host_hashes.txt');
const GHOST_STAGING_LEDGER_VERSION = '20261104000001';
const REHEARSAL_DATABASE_NAME = 'doctornect_rehearsal';
const DEFAULT_PRODUCTION_DATABASE_NAME = 'doctornect';

function hostHash8(hostname) {
  if (!hostname) return '';
  const normalized = String(hostname).trim().toLowerCase();
  return crypto.createHash('sha256').update(normalized, 'utf8').digest('hex').slice(0, 8).toUpperCase();
}

function isRdsCliTarget(target) {
  return target === 'production' || target === 'rehearsal';
}

function resolveCliMigrationTarget() {
  const targetArg = process.argv.find((a) => a.startsWith('--target='));
  if (!targetArg) {
    return 'staging';
  }
  const target = targetArg.split('=')[1].toLowerCase();
  if (
    target === 'staging' ||
    target === 'production' ||
    target === 'rehearsal' ||
    target === 'replay' ||
    target === 'replay_check'
  ) {
    return target;
  }
  return target;
}

function resolveLiveDataHostHash() {
  const target = resolveCliMigrationTarget();
  if (target === 'production' || target === 'rehearsal') {
    const rds = getEnv('PROD_RDS_HOST');
    return hostHash8(rds);
  }
  if (target === 'replay' || target === 'replay_check') {
    const replayUrl = getEnv('REPLAY_DB_URL');
    return hostHash8(getHostFingerprint(replayUrl));
  }
  const restUrl =
    getEnv('STAGING_SUPABASE_URL') ||
    getEnv('SUPABASE_URL') ||
    getEnv('STAGING_SUPABASE_DB_URL') ||
    getEnv('PROD_SUPABASE_DB_URL');
  const hostname = getHostFingerprint(restUrl);
  return hostHash8(hostname);
}

function resolveExpectedDatabaseName(target) {
  if (target === 'rehearsal') {
    return REHEARSAL_DATABASE_NAME;
  }
  if (target === 'production') {
    const fromEnv = getEnv('PROD_RDS_DB');
    return String(fromEnv || DEFAULT_PRODUCTION_DATABASE_NAME).trim().toLowerCase();
  }
  return null;
}

function parseConfirmDatabaseArg(args) {
  const arg = args.find((a) => a.startsWith('--confirm-db='));
  if (!arg) return null;
  return arg
    .slice('--confirm-db='.length)
    .trim()
    .toLowerCase();
}

function describeLiveDataGuardTarget(target) {
  const dbName = resolveExpectedDatabaseName(target);
  switch (target) {
    case 'production':
      return {
        label: `production AWS RDS (database ${dbName || DEFAULT_PRODUCTION_DATABASE_NAME})`,
        envHint: 'PROD_RDS_HOST',
        databaseName: dbName,
      };
    case 'rehearsal':
      return {
        label: `rehearsal RDS (database ${REHEARSAL_DATABASE_NAME})`,
        envHint: 'PROD_RDS_HOST',
        databaseName: REHEARSAL_DATABASE_NAME,
      };
    case 'replay':
      return { label: 'local replay database', envHint: 'REPLAY_DB_URL' };
    case 'replay_check':
      return { label: 'local replay_check database', envHint: 'REPLAY_DB_URL' };
    default:
      return { label: 'staging Supabase Postgres', envHint: 'STAGING_SUPABASE_DB_URL' };
  }
}

function formatLiveDataGuardHelp(scriptName, target) {
  const lines = [];
  lines.push(
    'Add --confirm-live-data to acknowledge configured live/reachable database access (see docs/audit/allowed_host_hashes.txt).',
  );
  if (target === 'production' || target === 'rehearsal') {
    const dbName = resolveExpectedDatabaseName(target) || '<database>';
    lines.push(
      `Dry-run: node ${scriptName} --target=${target} --dry-run-all --confirm-live-data --confirm=<PROD_RDS_HOST> --confirm-db=${dbName}`,
    );
    lines.push(
      `Apply (destructive): node ${scriptName} --target=${target} --execute --confirm-live-data --confirm=<PROD_RDS_HOST> --confirm-db=${dbName}`,
    );
  } else if (target === 'replay' || target === 'replay_check') {
    lines.push(`Dry-run: node ${scriptName} --target=${target} --dry-run-all --confirm-live-data`);
    lines.push(`Apply: node ${scriptName} --target=${target} --execute --confirm-live-data`);
  } else {
    lines.push(
      `Dry-run: node ${scriptName} --target=staging --dry-run-all --confirm-live-data`,
    );
    lines.push(
      `Apply (destructive): node ${scriptName} --target=staging --execute --confirm-live-data --confirm-staging`,
    );
  }
  return lines;
}

function usesServiceAccountPath() {
  const gac = getEnv('GOOGLE_APPLICATION_CREDENTIALS');
  return Boolean(gac && gac.trim());
}

function loadAllowedHashes() {
  const allowPath = process.env.DOCTORNECT_ALLOWED_HOST_HASHES || ALLOWLIST_PATH;
  if (!fs.existsSync(allowPath)) return new Set();
  const lines = fs.readFileSync(allowPath, 'utf8').split('\n');
  const allowed = new Set();
  for (const line of lines) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    allowed.add(t.toUpperCase());
  }
  return allowed;
}

/**
 * Guard mutating scripts that touch live staging data or Firebase via ADC.
 * Refusal prints exactly: "<HASH> <scriptName>" (no hostnames or secrets).
 */
function assertConfirmLiveData(scriptName) {
  const args = process.argv.slice(2);
  const target = resolveCliMigrationTarget();
  const { label } = describeLiveDataGuardTarget(target);
  const hash = resolveLiveDataHostHash();
  const adc = usesServiceAccountPath();

  if (isRdsCliTarget(target)) {
    const rdsHost = getEnv('PROD_RDS_HOST');
    if (!rdsHost || !String(rdsHost).trim()) {
      console.error(
        `[LIVE DATA GUARD] Refusing ${scriptName}: --target=${target} requires PROD_RDS_HOST (ADC cannot bypass RDS confirmation).`,
      );
      process.exit(1);
    }
    if (!hash) {
      console.error(
        `[LIVE DATA GUARD] Refusing ${scriptName}: could not derive RDS host fingerprint for --target=${target}.`,
      );
      process.exit(1);
    }
  } else if (!hash && !adc) {
    return { hash: '', dryRun: true, confirmed: false, skipped: true };
  }

  if (!args.includes('--confirm-live-data')) {
    const labelHash = hash || 'ADC_ONLY';
    console.error(
      `[LIVE DATA GUARD] Refusing to run ${scriptName} against ${label} (host fingerprint ${labelHash}).`,
    );
    for (const line of formatLiveDataGuardHelp(scriptName, target)) {
      console.error(line);
    }
    console.error(`${labelHash} ${scriptName}`);
    process.exit(1);
  }

  const allowed = loadAllowedHashes();
  if (hash && allowed.size > 0 && !allowed.has(hash)) {
    console.error(
      `[LIVE DATA GUARD] Host fingerprint ${hash} is not in docs/audit/allowed_host_hashes.txt for ${scriptName}.`,
    );
    console.error(`${hash} ${scriptName}`);
    process.exit(1);
  }

  const expectedDb = resolveExpectedDatabaseName(target);
  if (expectedDb) {
    const confirmedDb = parseConfirmDatabaseArg(args);
    if (!confirmedDb || confirmedDb !== expectedDb) {
      console.error(
        `[LIVE DATA GUARD] Refusing ${scriptName}: database confirmation required for ${target} (expected --confirm-db=${expectedDb}, got ${confirmedDb || '<none>'}).`,
      );
      for (const line of formatLiveDataGuardHelp(scriptName, target)) {
        console.error(line);
      }
      console.error(`${hash || 'DB_ONLY'} ${scriptName}`);
      process.exit(1);
    }
  }

  const execute = args.includes('--execute');
  return {
    hash,
    dryRun: !execute,
    confirmed: true,
    skipped: false,
  };
}

function isDryRunDefault() {
  const args = process.argv.slice(2);
  return !args.includes('--execute');
}

/**
 * After connect, ensure the session database matches --confirm-db / target (production vs rehearsal).
 * @param {{ query: (sql: string) => Promise<{ rows: Array<{ db?: string }> }> }} client
 * @param {string} scriptName
 */
async function assertConnectedDatabaseMatchesConfirm(client, scriptName) {
  const target = resolveCliMigrationTarget();
  const expectedDb = resolveExpectedDatabaseName(target);
  if (!expectedDb) {
    return;
  }

  const confirmedDb = parseConfirmDatabaseArg(process.argv.slice(2));
  let actualDb = '';
  try {
    const res = await client.query('SELECT current_database() AS db');
    actualDb = String(res.rows[0]?.db || '').trim().toLowerCase();
  } catch (err) {
    console.error(
      `[LIVE DATA GUARD] Could not verify current_database() for ${scriptName}: ${err?.message || err}`,
    );
    process.exit(1);
  }

  if (!actualDb || actualDb !== expectedDb || (confirmedDb && actualDb !== confirmedDb)) {
    console.error(
      `[LIVE DATA GUARD] Connected database "${actualDb || '<unknown>'}" does not match ` +
        `--confirm-db=${confirmedDb || expectedDb} (target=${target}). Aborting ${scriptName}.`,
    );
    process.exit(1);
  }
}

module.exports = {
  hostHash8,
  isRdsCliTarget,
  resolveCliMigrationTarget,
  resolveLiveDataHostHash,
  describeLiveDataGuardTarget,
  formatLiveDataGuardHelp,
  assertConfirmLiveData,
  isDryRunDefault,
  resolveExpectedDatabaseName,
  parseConfirmDatabaseArg,
  assertConnectedDatabaseMatchesConfirm,
  ALLOWLIST_PATH,
  GHOST_STAGING_LEDGER_VERSION,
  REHEARSAL_DATABASE_NAME,
  DEFAULT_PRODUCTION_DATABASE_NAME,
};