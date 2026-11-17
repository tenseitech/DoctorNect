'use strict';

const fs = require('fs');
const path = require('path');

/** Prefixes that must never be duplicated in repo root `.env` (fail-fast at load). */
const PRODUCTION_ENV_KEY_PREFIXES = ['PROD_', 'REPLAY_', 'LOCAL_REPLAY_', 'PGRST_'];

function isProductionRelatedEnvKey(key) {
  return PRODUCTION_ENV_KEY_PREFIXES.some((p) => key.startsWith(p));
}

/**
 * Parse assignment lines; returns duplicates (key appears on 2+ lines). Values never returned.
 * @param {string} content
 * @returns {{ key: string, lines: number[] }[]}
 */
function findDuplicateEnvKeysInContent(content) {
  const keyLines = new Map();
  const lines = content.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const lineNum = i + 1;
    const trimmed = lines[i].trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx === -1) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue;
    if (!keyLines.has(key)) keyLines.set(key, []);
    keyLines.get(key).push(lineNum);
  }
  const duplicates = [];
  for (const [key, nums] of keyLines) {
    if (nums.length > 1) {
      duplicates.push({ key, lines: [...nums] });
    }
  }
  duplicates.sort((a, b) => a.lines[0] - b.lines[0] || a.key.localeCompare(b.key));
  return duplicates;
}

/**
 * @param {string} filePath
 * @returns {{ key: string, lines: number[] }[]}
 */
function findDuplicateEnvKeysInFile(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return [];
  const content = fs.readFileSync(filePath, 'utf8');
  return findDuplicateEnvKeysInContent(content);
}

function formatDuplicateKeyLines(dup) {
  return dup.lines.join(', ');
}

/**
 * @param {string} label e.g. ".env"
 * @param {{ key: string, lines: number[] }[]} duplicates
 */
function formatDuplicateEnvReport(label, duplicates) {
  if (!duplicates.length) return '';
  const rows = duplicates.map(
    (d) => `  Duplicate key "${d.key}" in ${label} at lines ${formatDuplicateKeyLines(d)}`,
  );
  return rows.join('\n');
}

function assertNoProductionDuplicateKeys(filePath) {
  const dups = findDuplicateEnvKeysInFile(filePath);
  const prod = dups.filter((d) => isProductionRelatedEnvKey(d.key));
  if (!prod.length) return;
  const label = path.basename(filePath);
  const err = new Error(
    `Refusing to load ${label}: duplicate production-related env key(s).\n${formatDuplicateEnvReport(label, prod)}`,
  );
  err.code = 'ENV_DUPLICATE_PRODUCTION_KEY';
  err.duplicates = prod;
  throw err;
}

/**
 * @param {string} filePath
 * @param {{ productionOnly?: boolean }} options
 */
function assertNoDuplicateEnvKeys(filePath, options = {}) {
  const productionOnly = options.productionOnly === true;
  const dups = findDuplicateEnvKeysInFile(filePath);
  const filtered = productionOnly ? dups.filter((d) => isProductionRelatedEnvKey(d.key)) : dups;
  if (!filtered.length) return;
  const label = path.basename(filePath);
  const err = new Error(
    `Duplicate env key(s) in ${label}.\n${formatDuplicateEnvReport(label, filtered)}`,
  );
  err.code = productionOnly ? 'ENV_DUPLICATE_PRODUCTION_KEY' : 'ENV_DUPLICATE_KEY';
  err.duplicates = filtered;
  throw err;
}

function verifyRootEnvFilesNoDuplicateKeys(rootDir) {
  const failures = [];
  for (const name of ['.env', '.env.example']) {
    const filePath = path.join(rootDir, name);
    if (!fs.existsSync(filePath)) continue;
    const dups = findDuplicateEnvKeysInFile(filePath);
    if (dups.length) {
      failures.push({ file: name, duplicates: dups });
    }
  }
  return failures;
}

module.exports = {
  PRODUCTION_ENV_KEY_PREFIXES,
  isProductionRelatedEnvKey,
  findDuplicateEnvKeysInContent,
  findDuplicateEnvKeysInFile,
  formatDuplicateEnvReport,
  assertNoProductionDuplicateKeys,
  assertNoDuplicateEnvKeys,
  verifyRootEnvFilesNoDuplicateKeys,
};
