'use strict';

const path = require('path');
const { findRepoRoot } = require('./repo_root');
const { parseEnvFile } = require('./parse_env_file');
const { loadRootEnv } = require('./bootstrap_root_env');

const rootDir = findRepoRoot(path.join(__dirname, '..'));
loadRootEnv({ startDir: rootDir });
const rootEnv = parseEnvFile(path.join(rootDir, '.env'));
const mergedEnv = { ...rootEnv, ...process.env };

function getEnv(key) {
  if (Object.prototype.hasOwnProperty.call(process.env, key) && process.env[key] !== '') {
    return process.env[key];
  }
  return mergedEnv[key] || '';
}

function hasEnv(key) {
  return Boolean(mergedEnv[key]);
}

function maskConnectionString(uri) {
  if (!uri) return '<EMPTY>';
  try {
    const parsed = new URL(uri);
    if (parsed.password) {
      parsed.password = '****';
    }
    return parsed.toString();
  } catch (_) {
    return uri.replace(/:([^:@]+)@/, ':****@');
  }
}

function printEnvSummary(keys) {
  console.log('\n--- Environment Keys Audit (Values Hidden) ---');
  for (const k of keys) {
    const v = mergedEnv[k];
    if (v) {
      console.log(`[PRESENT] ${k}: (length: ${v.length})`);
    } else {
      console.log(`[MISSING] ${k}`);
    }
  }
  console.log('-----------------------------------------------\n');
}

module.exports = {
  getEnv,
  hasEnv,
  maskConnectionString,
  printEnvSummary,
  mergedEnv,
};
