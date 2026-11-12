'use strict';

const fs = require('fs');
const path = require('path');

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const content = fs.readFileSync(filePath, 'utf8');
  const env = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx !== -1) {
      const key = trimmed.slice(0, eqIdx).trim();
      let val = trimmed.slice(eqIdx + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      env[key] = val;
    }
  }
  return env;
}

const rootDir = path.resolve(__dirname, '../..');
const rootEnv = parseEnvFile(path.join(rootDir, '.env'));
const migEnv = parseEnvFile(path.join(rootDir, '.env.migration'));
const backendEnv = parseEnvFile(path.join(rootDir, 'backend/functions/.env'));
const mergedEnv = { ...rootEnv, ...migEnv, ...backendEnv, ...process.env };

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
