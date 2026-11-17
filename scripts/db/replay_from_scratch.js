'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { Client } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { getHostFingerprint } = require('../lib/env_guard');
const { bootstrapMutatingScript } = require('../lib/mutating_script_bootstrap');
const { getReplayPgDockerTag, getProdPgVersion } = require('../lib/pg_version_policy');

async function checkDockerAvailable() {
  try {
    execSync('docker ps', { stdio: 'pipe' });
    return true;
  } catch (_) {
    return false;
  }
}

async function replayFromScratch() {
  bootstrapMutatingScript('scripts/db/replay_from_scratch.js');
  console.log('======================================================');
  console.log('DoctorNect: From-Scratch Migration Replay & Verification');
  console.log('======================================================\n');

  const replayDbUrl = getEnv('REPLAY_DB_URL');
  const stagingDbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  const prodRdsHost = getEnv('PROD_RDS_HOST');

  const stagingFingerprint = getHostFingerprint(stagingDbUrl);
  const prodFingerprint = getHostFingerprint(prodRdsHost);

  // Guard: Refuse staging and prod fingerprints
  if (replayDbUrl) {
    const replayFingerprint = getHostFingerprint(replayDbUrl);
    if (replayFingerprint === stagingFingerprint || replayFingerprint === prodFingerprint) {
      console.error(`\n[GUARD BLOCKED] REPLAY_DB_URL targets a protected database (${replayFingerprint})!`);
      console.error('Replay must only run against an isolated throwaway database.');
      process.exit(1);
    }
  }

  const dockerAvailable = await checkDockerAvailable();

  if (!replayDbUrl && !dockerAvailable) {
    console.log('[PREREQUISITES MISSING]');
    console.log('1. REPLAY_DB_URL environment variable is not configured.');
    console.log('2. Docker engine is not running (docker ps failed).');
    console.log('\nTo run a from-scratch replay:');
    console.log('- Provide an isolated scratch PostgreSQL 18 instance: export REPLAY_DB_URL=postgresql://postgres:pass@127.0.0.1:5440/postgres');
    console.log(
      `- OR start Docker Desktop / daemon for automated postgres:${getReplayPgDockerTag()} container provisioning.`,
    );
    console.log('\nSkipping replay step without failure. Continuing pipeline.');
    return { status: 'SKIPPED', reason: 'Prerequisites not met (no REPLAY_DB_URL, Docker unavailable)' };
  }

  let targetUrl = replayDbUrl;
  let containerId = null;

  if (!targetUrl && dockerAvailable) {
    const dockerTag = getReplayPgDockerTag();
    console.log(`Docker detected. Provisioning temporary postgres:${dockerTag} container (target PROD_PG_VERSION=${getProdPgVersion()})...`);
    try {
      const defaultPort = getEnv('LOCAL_REPLAY_PG_PORT') || '5440';
      const hostPort = process.env.REPLAY_DOCKER_PORT || defaultPort;
      const runOut = execSync(
        `docker run -d --rm -e POSTGRES_PASSWORD=scratchpass -p ${hostPort}:5432 postgres:${dockerTag}`,
        { encoding: 'utf8' },
      );
      containerId = runOut.trim();
      targetUrl = `postgresql://postgres:scratchpass@127.0.0.1:${hostPort}/postgres`;
      console.log(`Ephemeral Postgres container started: ${containerId.slice(0, 12)} on port ${hostPort}`);
      // Wait for postgres to be ready
      await new Promise(r => setTimeout(r, 4000));
    } catch (e) {
      console.error('Failed to start Docker postgres:18:', e.message);
      return { status: 'SKIPPED', reason: 'Docker container launch failed' };
    }
  }

  console.log(`Connecting to replay database: ${maskConnectionString(targetUrl)}`);
  const client = new Client({ connectionString: targetUrl });
  try {
    await client.connect();
    console.log('Connected to replay database.');

    // 1. Run bootstrap shim for vanilla Postgres (auth schema, roles, etc.)
    console.log('Applying bootstrap shim for isolated postgres...');
    await client.query(`
      CREATE SCHEMA IF NOT EXISTS auth;
      CREATE SCHEMA IF NOT EXISTS private;
      DO $$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
      END $$;
      CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
        SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
      $$;
    `);

    // 2. Apply all migrations in order
    const migrationsDir = path.resolve(__dirname, '../../db/migrations');
    const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();
    console.log(`Applying ${files.length} migrations in sequence from scratch...`);

    for (const f of files) {
      const sql = fs.readFileSync(path.join(migrationsDir, f), 'utf8');
      try {
        await client.query(sql);
      } catch (err) {
        console.error(`Error applying migration ${f} on scratch database: ${err.message}`);
        throw err;
      }
    }
    console.log(`✔ All ${files.length} migrations applied successfully from scratch!`);

    return { status: 'SUCCESS', target: maskConnectionString(targetUrl) };
  } finally {
    await client.end().catch(() => {});
    if (containerId) {
      try {
        execSync(`docker stop ${containerId}`, { stdio: 'pipe' });
        console.log(`Ephemeral container ${containerId.slice(0, 12)} stopped and cleaned up.`);
      } catch (_) {}
    }
  }
}

if (require.main === module) {
  replayFromScratch().catch(err => {
    console.error('Replay failed:', err);
    process.exit(1);
  });
}

module.exports = { replayFromScratch };

