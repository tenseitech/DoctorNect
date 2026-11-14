'use strict';

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '../..');
const MIGRATIONS_ROOT = path.join(REPO_ROOT, 'db/migrations');
const RDS_OVERRIDES_ROOT = path.join(REPO_ROOT, 'db/rds_overrides');

const MIGRATION_ADVISORY_LOCK_KEYS = Object.freeze({ classId: 20260923, objectId: 42 });
const MIGRATION_VERSION_PATTERN = /^\d{14}$/;

function migrationVersionFromRel(relPath) {
  return path.basename(relPath).split('_')[0];
}

function assertMigrationVersionFormats(relPaths) {
  for (const rel of relPaths) {
    const version = migrationVersionFromRel(rel);
    if (!MIGRATION_VERSION_PATTERN.test(version)) {
      throw new Error(
        `Invalid migration filename (version must be exactly 14 digits): ${rel} (parsed prefix "${version}")`,
      );
    }
  }
}

function assertVersionCollisions(relPaths) {
  const byVersion = new Map();
  for (const rel of relPaths) {
    const version = migrationVersionFromRel(rel);
    const list = byVersion.get(version) || [];
    list.push(rel);
    byVersion.set(version, list);
  }
  const collisions = [];
  for (const [version, files] of byVersion) {
    if (files.length > 1) {
      collisions.push({ version, files });
    }
  }
  if (collisions.length) {
    const detail = collisions
      .map((c) => `${c.version} → ${c.files.join(' AND ')}`)
      .join('; ');
    throw new Error(`Migration version collision (duplicate version prefix): ${detail}`);
  }
}

function sortMigrationRelPaths(relPaths) {
  return [...relPaths].sort((a, b) => {
    const va = migrationVersionFromRel(a);
    const vb = migrationVersionFromRel(b);
    if (va !== vb) {
      return va < vb ? -1 : 1;
    }
    if (a === b) {
      return 0;
    }
    return a < b ? -1 : 1;
  });
}

function listSharedMigrationRelPathsFromDir(migrationsRoot) {
  if (!fs.existsSync(migrationsRoot)) {
    throw new Error(`empty migrations dir: ${migrationsRoot} does not exist`);
  }
  const shared = fs
    .readdirSync(migrationsRoot)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  if (shared.length === 0) {
    throw new Error(`empty migrations dir: no .sql files in ${migrationsRoot}`);
  }
  return shared;
}

function listSharedMigrationRelPaths() {
  return listSharedMigrationRelPathsFromDir(MIGRATIONS_ROOT);
}

function listRdsOnlyMigrationRelPaths() {
  const rdsDir = path.join(MIGRATIONS_ROOT, 'rds');
  if (!fs.existsSync(rdsDir)) {
    return [];
  }
  return fs
    .readdirSync(rdsDir)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => `rds/${f}`);
}

/**
 * @param {'staging'|'production'|'rehearsal'|'replay'|'replay_check'} target
 */
function listMigrationsForTarget(target) {
  const shared = listSharedMigrationRelPaths();
  const normalized = String(target || 'staging').toLowerCase();
  const includeRds =
    normalized === 'production' ||
    normalized === 'rehearsal' ||
    normalized === 'replay' ||
    normalized === 'replay_check';
  const combined = includeRds ? [...shared, ...listRdsOnlyMigrationRelPaths()] : shared;
  assertMigrationVersionFormats(combined);
  assertVersionCollisions(combined);
  return sortMigrationRelPaths(combined);
}

function migrationRelPathToAbs(relPath) {
  const parts = String(relPath).split('/').filter(Boolean);
  return path.join(MIGRATIONS_ROOT, ...parts);
}

function resolveMigrationSqlPath({
  relPath,
  target,
  overridesRoot = RDS_OVERRIDES_ROOT,
}) {
  const baseName = path.basename(relPath);
  const baseSqlPath = migrationRelPathToAbs(relPath);
  const useRdsOverride =
    target === 'production' ||
    target === 'rehearsal' ||
    target === 'replay' ||
    target === 'replay_check';
  const overrideSqlPath = path.join(overridesRoot, baseName);
  if (useRdsOverride && fs.existsSync(overrideSqlPath)) {
    return { sqlPath: overrideSqlPath, useOverride: true };
  }
  return { sqlPath: baseSqlPath, useOverride: false };
}

module.exports = {
  REPO_ROOT,
  MIGRATIONS_ROOT,
  RDS_OVERRIDES_ROOT,
  MIGRATION_ADVISORY_LOCK_KEYS,
  listSharedMigrationRelPaths,
  listSharedMigrationRelPathsFromDir,
  listRdsOnlyMigrationRelPaths,
  listMigrationsForTarget,
  migrationRelPathToAbs,
  migrationVersionFromRel,
  MIGRATION_VERSION_PATTERN,
  assertMigrationVersionFormats,
  assertVersionCollisions,
  sortMigrationRelPaths,
  resolveMigrationSqlPath,
};
