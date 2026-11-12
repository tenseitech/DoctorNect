'use strict';

const { getEnv, maskConnectionString } = require('./env_loader');

function getHostFingerprint(uriOrHost) {
  if (!uriOrHost) return '';
  const trimmed = uriOrHost.trim();
  if (!trimmed.includes('://')) {
    return trimmed.split(':')[0].trim().toLowerCase();
  }
  try {
    const parsed = new URL(trimmed);
    return parsed.hostname.toLowerCase();
  } catch (_) {
    return trimmed.split(':')[0].trim().toLowerCase();
  }
}

/**
 * Validates that an operation targeting a database is explicitly authorized.
 * 
 * Rules:
 * - Target kind: 'staging' | 'production'
 * - Destructive or test scripts targeting staging require --confirm-staging in CLI args.
 * - Operations targeting production require --target=production and --confirm=<RDS host>.
 * - Fingerprint comparison ensures no cross-target confusion.
 */
function assertDatabaseGuard({ targetKind, operationName = 'Database Operation', allowDestructive = false, targetHost = null }) {
  const args = process.argv.slice(2);
  const stagingDbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  const prodRdsHost = getEnv('PROD_RDS_HOST');

  const stagingFingerprint = getHostFingerprint(stagingDbUrl);
  const prodFingerprint = getHostFingerprint(prodRdsHost);

  if (targetKind === 'replay' || targetKind === 'replay_check') {
    return {
      targetKind: 'replay',
      host: 'replay_check',
    };
  }

  if (targetKind === 'staging') {
    if (!stagingDbUrl) {
      console.error(`\n[GUARD ABORT] ${operationName}: STAGING_SUPABASE_DB_URL is not configured.`);
      process.exit(1);
    }

    if (allowDestructive) {
      const hasConfirm = args.includes('--confirm-staging');
      if (!hasConfirm) {
        console.error(`\n[GUARD BLOCKED] ${operationName} is DESTRUCTIVE/TEST.`);
        console.error(`Target: STAGING (${maskConnectionString(stagingDbUrl)})`);
        console.error(`To proceed against staging, pass explicit flag: --confirm-staging\n`);
        process.exit(1);
      }
    }

    const customHostArg = args.find(a => a.startsWith('--host=') || a.startsWith('--db='));
    const candidateHost = targetHost || (customHostArg ? customHostArg.split('=')[1] : null);
    if (candidateHost && getHostFingerprint(candidateHost) !== stagingFingerprint) {
      console.error(`\n[GUARD BLOCKED] ${operationName}: Host "${candidateHost}" does not match staging fingerprint "${stagingFingerprint}".`);
      process.exit(1);
    }

    return {
      targetKind: 'staging',
      host: stagingFingerprint,
      dbUrl: stagingDbUrl,
    };
  }

  if (targetKind === 'production') {
    if (!prodRdsHost) {
      console.error(`\n[GUARD ABORT] ${operationName}: PROD_RDS_HOST is not configured.`);
      process.exit(1);
    }

    const targetArg = args.find(a => a.startsWith('--target='));
    const confirmArg = args.find(a => a.startsWith('--confirm='));

    const requestedTarget = targetArg ? targetArg.split('=')[1] : null;
    const confirmedHost = confirmArg ? confirmArg.split('=')[1] : null;

    if (requestedTarget !== 'production') {
      console.error(`\n[GUARD BLOCKED] ${operationName} targets PRODUCTION.`);
      console.error(`Must explicitly provide CLI argument: --target=production\n`);
      process.exit(1);
    }

    if (!confirmedHost || confirmedHost.toLowerCase() !== prodFingerprint) {
      console.error(`\n[GUARD BLOCKED] ${operationName} targets PRODUCTION.`);
      console.error(`Must explicitly confirm the exact RDS host matching fingerprint.`);
      console.error(`Provided: ${confirmedHost || '<none>'}`);
      console.error(`Required: --confirm=${prodFingerprint}\n`);
      process.exit(1);
    }

    return {
      targetKind: 'production',
      host: prodFingerprint,
    };
  }

  console.error(`\n[GUARD ABORT] Unknown targetKind: ${targetKind}`);
  process.exit(1);
}

module.exports = {
  getHostFingerprint,
  assertDatabaseGuard,
};
