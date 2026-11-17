'use strict';

const fs = require('fs');
const {
  assertNoProductionDuplicateKeys,
  findDuplicateEnvKeysInContent,
} = require('./env_duplicate_keys');

/**
 * @param {string} filePath
 * @param {{ failOnProductionDuplicateKeys?: boolean }} [options]
 */
function parseEnvFile(filePath, options = {}) {
  if (!filePath || !fs.existsSync(filePath)) return {};
  const content = fs.readFileSync(filePath, 'utf8');
  const failOnProductionDuplicateKeys = options.failOnProductionDuplicateKeys !== false;
  if (failOnProductionDuplicateKeys) {
    assertNoProductionDuplicateKeys(filePath);
  }
  const env = {};
  const lines = content.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx === -1) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue;
    let val = trimmed.slice(eqIdx + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    env[key] = val;
  }
  return env;
}

function serializeEnvFile(sections) {
  const lines = [];
  for (const block of sections) {
    lines.push(`# ${block.title}`);
    if (block.comment) lines.push(`# ${block.comment}`);
    lines.push('');
    for (const [key, value] of block.entries) {
      const safe = String(value ?? '').includes(' ') ? `"${value}"` : String(value ?? '');
      lines.push(`${key}=${safe}`);
    }
    lines.push('');
  }
  return `${lines.join('\n').trim()}\n`;
}

module.exports = {
  parseEnvFile,
  serializeEnvFile,
  findDuplicateEnvKeysInContent,
};
