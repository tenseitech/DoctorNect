'use strict';

const { getEnv } = require('./env_loader');

const LOCAL_REPLAY_PORTS = new Set([5440, 55433]);

function parsePositiveInt(raw, fallback) {
  const n = parseInt(String(raw || '').trim(), 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

/** Production RDS target major (default 18). */
function getProdPgMajor() {
  return parsePositiveInt(getEnv('PROD_PG_MAJOR'), 18);
}

/** Documented production RDS full version (default 18.3 — major pinned separately). */
function getProdPgVersion() {
  const v = String(getEnv('PROD_PG_VERSION') || '18.3').trim();
  return v || '18.3';
}

/** Docker image tag for local replay (prefer exact production minor). */
function getReplayPgDockerTag() {
  return String(getEnv('REPLAY_PG_DOCKER_TAG') || getProdPgVersion()).trim();
}

/** Local throwaway replay DB major (default matches PROD_PG_MAJOR). */
function getReplayPgMajor() {
  return parsePositiveInt(getEnv('REPLAY_PG_MAJOR'), getProdPgMajor());
}

/** Parse `SHOW server_version` / first segment of `version()` into `major.minor`. */
function parseServerRelease(serverVersionRaw) {
  const m = String(serverVersionRaw || '').match(/(\d+)\.(\d+)/);
  if (!m) return null;
  return { major: parseInt(m[1], 10), minor: parseInt(m[2], 10), label: `${m[1]}.${m[2]}` };
}

function serverVersionMatchesProdTarget(serverVersionRaw, targetVersion = getProdPgVersion()) {
  const parsed = parseServerRelease(serverVersionRaw);
  const target = parseServerRelease(targetVersion);
  if (!parsed || !target) return false;
  return parsed.major === target.major && parsed.minor === target.minor;
}

function parseServerVersionNum(row) {
  const num = parseInt(String(row?.server_version_num ?? row ?? ''), 10);
  if (!Number.isFinite(num)) return null;
  return Math.floor(num / 10000);
}

function parseMajorFromVersionString(versionLine) {
  const m = String(versionLine || '').match(/PostgreSQL\s+(\d+)/i);
  return m ? parseInt(m[1], 10) : null;
}

/**
 * @param {{ versionLine?: string, serverVersionNum?: number }} info
 * @param {{ enforce?: boolean, label?: string }} options enforce=true → throw on mismatch
 */
function evaluatePgMajor(info, options = {}) {
  const enforce = options.enforce !== false;
  const label = options.label || 'database';
  const expected = options.expectedMajor ?? getProdPgMajor();
  const major =
    info.serverVersionNum != null
      ? info.serverVersionNum
      : parseMajorFromVersionString(info.versionLine);

  if (major == null) {
    const err = new Error(`Could not determine PostgreSQL major version for ${label}`);
    err.code = 'PG_VERSION_UNKNOWN';
    throw err;
  }

  const ok = major === expected;
  const line = `PostgreSQL major ${major} on ${label} (expected ${expected} when enforced=${enforce})`;
  if (enforce && !ok) {
    const err = new Error(`${line} — set PROD_PG_MAJOR=${expected} only when RDS matches.`);
    err.code = 'PG_MAJOR_MISMATCH';
    err.major = major;
    err.expected = expected;
    throw err;
  }
  return { major, expected, ok, line };
}

function isLocalReplayPort(port) {
  const p = parseInt(String(port), 10);
  if (LOCAL_REPLAY_PORTS.has(p)) return true;
  const fromEnv = parsePositiveInt(getEnv('LOCAL_REPLAY_PG_PORT'), 5440);
  return p === fromEnv;
}

module.exports = {
  getProdPgMajor,
  getProdPgVersion,
  getReplayPgDockerTag,
  getReplayPgMajor,
  parseServerRelease,
  serverVersionMatchesProdTarget,
  parseServerVersionNum,
  parseMajorFromVersionString,
  evaluatePgMajor,
  isLocalReplayPort,
  LOCAL_REPLAY_PORTS,
};
