'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { getEnv } = require('./env_loader');
const { getHostFingerprint } = require('./env_guard');

const ALLOWLIST_PATH = path.resolve(__dirname, '../../docs/audit/allowed_host_hashes.txt');

function hostHash8(hostname) {
  if (!hostname) return '';
  const normalized = String(hostname).trim().toLowerCase();
  return crypto.createHash('sha256').update(normalized, 'utf8').digest('hex').slice(0, 8).toUpperCase();
}

function resolveLiveDataHostHash() {
  const restUrl =
    getEnv('STAGING_SUPABASE_URL') ||
    getEnv('SUPABASE_URL') ||
    getEnv('STAGING_SUPABASE_DB_URL') ||
    getEnv('PROD_SUPABASE_DB_URL');
  const hostname = getHostFingerprint(restUrl);
  return hostHash8(hostname);
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
  const hash = resolveLiveDataHostHash();
  const adc = usesServiceAccountPath();

  if (!hash && !adc) {
    return { hash: '', dryRun: true, confirmed: false, skipped: true };
  }

  if (!args.includes('--confirm-live-data')) {
    const label = hash || 'ADC_ONLY';
    console.error(`${label} ${scriptName}`);
    process.exit(1);
  }

  const allowed = loadAllowedHashes();
  if (hash && allowed.size > 0 && !allowed.has(hash)) {
    console.error(`${hash} ${scriptName}`);
    process.exit(1);
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

module.exports = {
  hostHash8,
  resolveLiveDataHostHash,
  assertConfirmLiveData,
  isDryRunDefault,
  ALLOWLIST_PATH,
};
