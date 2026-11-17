'use strict';

const { Pool } = require('pg');

function scratchDatabaseName() {
  return `migrate_scratch_${Date.now()}`;
}

function quoteIdent(name) {
  return `"${String(name).replace(/"/g, '""')}"`;
}

/**
 * Create an isolated database on the same RDS instance for production dry-run-all.
 * Caller must DROP via withMigrateScratchDatabase finally block.
 */
async function createMigrateScratchDatabase(adminPool, ownerRole = 'doctornect_admin') {
  const dbName = scratchDatabaseName();
  const client = await adminPool.connect();
  try {
    await client.query(`CREATE DATABASE ${quoteIdent(dbName)} OWNER ${quoteIdent(ownerRole)}`);
    return dbName;
  } finally {
    client.release();
  }
}

async function dropMigrateScratchDatabase(adminPool, dbName) {
  if (!dbName) return;
  const client = await adminPool.connect();
  try {
    await client.query(
      `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()`,
      [dbName],
    );
    await client.query(`DROP DATABASE IF EXISTS ${quoteIdent(dbName)} WITH (FORCE)`);
  } finally {
    client.release();
  }
}

/**
 * @param {import('pg').PoolConfig} basePoolConfig
 * @param {(scratchPool: Pool) => Promise<void>} fn
 */
async function withMigrateScratchDatabase(basePoolConfig, fn) {
  const adminDatabase = basePoolConfig.database === 'postgres' ? 'postgres' : 'postgres';
  const adminPool = new Pool({ ...basePoolConfig, database: adminDatabase });
  let scratchName = null;
  const owner = basePoolConfig.user || 'doctornect_admin';
  try {
    scratchName = await createMigrateScratchDatabase(adminPool, owner);
    const scratchPool = new Pool({ ...basePoolConfig, database: scratchName });
    try {
      await fn(scratchPool);
    } finally {
      await scratchPool.end();
    }
  } finally {
    await dropMigrateScratchDatabase(adminPool, scratchName);
    await adminPool.end();
  }
}

module.exports = {
  scratchDatabaseName,
  withMigrateScratchDatabase,
  createMigrateScratchDatabase,
  dropMigrateScratchDatabase,
  quoteIdent,
};