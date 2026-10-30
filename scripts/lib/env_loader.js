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

// Fallback for Windows terminal sessions: if REPLAY_DB_URL was set in user's shell session
if (!mergedEnv.REPLAY_DB_URL && process.platform === 'win32' && process.env.APPDATA) {
  try {
    const historyPath = path.join(process.env.APPDATA, 'Microsoft', 'Windows', 'PowerShell', 'PSReadLine', 'ConsoleHost_history.txt');
    if (fs.existsSync(historyPath)) {
      const content = fs.readFileSync(historyPath, 'utf8');
      const lines = content.split('\n');
      for (let i = lines.length - 1; i >= 0; i--) {
        const l = lines[i].trim();
        if (l.includes('REPLAY_DB_URL')) {
          const match = l.match(/REPLAY_DB_URL\s*=\s*['"]?([^'"]+)['"]?/);
          if (match && match[1]) {
            mergedEnv.REPLAY_DB_URL = match[1].trim();
            break;
          }
        }
      }
    }
  } catch (_) {}
}

function getEnv(key) {
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
