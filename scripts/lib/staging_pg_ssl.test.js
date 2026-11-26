'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { buildStagingPgConfig, CA_PATH_ENV } = require('./staging_pg_ssl');

const POOLER = 'postgresql://postgres.abcd:pw@aws-0-ap-south-1.pooler.supabase.com:5432/postgres';
const PEM = '-----BEGIN CERTIFICATE-----\nMIIBfake\n-----END CERTIFICATE-----\n';
const reader = (files) => (p) => {
  if (!(p in files)) { const e = new Error('nope'); e.code = 'ENOENT'; throw e; }
  return files[p];
};

test('Supabase host with CA file: full verification (chain + hostname), never rejectUnauthorized=false', () => {
  const ca = path.resolve('/certs/prod-ca-2021.crt');
  const cfg = buildStagingPgConfig(POOLER, { env: { [CA_PATH_ENV]: ca }, readFile: reader({ [ca]: PEM }) });
  assert.equal(cfg.ssl.rejectUnauthorized, true);
  assert.equal(cfg.ssl.ca, PEM);
  assert.equal(cfg.ssl.servername, 'aws-0-ap-south-1.pooler.supabase.com');
  assert.equal(cfg.ssl.checkServerIdentity, undefined, 'default hostname check must stay on');
  assert.equal(cfg.verified, true);
});

test('relative CA path resolves against the repo root', () => {
  const root = path.resolve('/repo');
  const ca = path.join(root, 'certs', 'supabase.crt');
  const cfg = buildStagingPgConfig(POOLER, {
    env: { [CA_PATH_ENV]: 'certs/supabase.crt' }, repoRoot: root, readFile: reader({ [ca]: PEM }),
  });
  assert.equal(cfg.ssl.ca, PEM);
});

test('Supabase host without CA file is refused with guidance (no insecure fallback)', () => {
  assert.throws(() => buildStagingPgConfig(POOLER, { env: {} }), (e) => {
    assert.match(e.message, /STAGING_SUPABASE_CA_PATH is not set/);
    assert.match(e.message, /Supabase Root 2021 CA/);
    assert.doesNotMatch(e.message, /pw@|postgres\.abcd/, 'connection string must not leak');
    return true;
  });
  assert.throws(() => buildStagingPgConfig('postgresql://u:p@db.abcd.supabase.co:5432/postgres', { env: {} }));
});

test('unreadable or non-PEM CA file is refused', () => {
  assert.throws(() => buildStagingPgConfig(POOLER, { env: { [CA_PATH_ENV]: '/missing.crt' }, readFile: reader({}) }), /cannot be read \(ENOENT\)/);
  const p = path.resolve('/x.crt');
  assert.throws(() => buildStagingPgConfig(POOLER, { env: { [CA_PATH_ENV]: p }, readFile: reader({ [p]: 'not a cert' }) }), /not a PEM/);
});

test('ssl params are stripped from the URL so they cannot override the verified ssl object', () => {
  const ca = path.resolve('/ca.crt');
  const cfg = buildStagingPgConfig(`${POOLER}?sslmode=require&sslrootcert=/tmp/x&uselibpqcompat=true&application_name=seed`, {
    env: { [CA_PATH_ENV]: ca }, readFile: reader({ [ca]: PEM }),
  });
  const u = new URL(cfg.connectionString);
  assert.equal(u.searchParams.get('sslmode'), null);
  assert.equal(u.searchParams.get('sslrootcert'), null);
  assert.equal(u.searchParams.get('uselibpqcompat'), null);
  assert.equal(u.searchParams.get('application_name'), 'seed');
  // pg merges connection-string options over config; confirm nothing ssl-related survives.
  const parse = require(require.resolve('pg-connection-string', { paths: [require.resolve('pg', { paths: [__dirname] })] })).parse;
  assert.equal(parse(cfg.connectionString).ssl, undefined);
});

test('sslmode=disable/prefer/allow on a remote host is refused', () => {
  for (const m of ['disable', 'prefer', 'allow']) {
    assert.throws(() => buildStagingPgConfig(`${POOLER}?sslmode=${m}`, { env: {} }), /not allowed/);
  }
});

test('loopback: plain TCP only when the caller allows local (Docker e2e)', () => {
  const local = 'postgresql://postgres:pw@127.0.0.1:55432/postgres';
  assert.equal(buildStagingPgConfig(local, { allowLocal: true, env: {} }).ssl, false);
  assert.throws(() => buildStagingPgConfig(local, { env: {} }), /refusing loopback/);
});

test('non-Supabase host without CA verifies against Node public roots', () => {
  const cfg = buildStagingPgConfig('postgresql://u:p@db.example.org:5432/postgres', { env: {} });
  assert.deepEqual(cfg.ssl, { rejectUnauthorized: true, servername: 'db.example.org' });
});

test('invalid URL error does not echo the value', () => {
  assert.throws(() => buildStagingPgConfig('not a url with secret', { env: {} }), (e) => !e.message.includes('secret'));
});

test('seed, migrate and sync_ledger_checksum use the shared helper and never disable verification', () => {
  for (const rel of ['../db/seed_staging_demo_accounts.js', '../db/migrate.js', '../db/sync_ledger_checksum.js']) {
    const src = fs.readFileSync(path.join(__dirname, rel), 'utf8');
    assert.match(src, /require\('\.\.\/lib\/staging_pg_ssl'\)/, `${rel} must use staging_pg_ssl`);
    assert.doesNotMatch(src, /rejectUnauthorized:\s*false/, `${rel} must not disable verification`);
    assert.doesNotMatch(src, /NODE_TLS_REJECT_UNAUTHORIZED/, rel);
  }
});

test('migrate.buildStagingPoolConfig returns the verified config', () => {
  const { buildStagingPoolConfig } = require('../db/migrate');
  const prev = process.env[CA_PATH_ENV];
  const tmp = path.join(require('os').tmpdir(), `staging-ca-test-${process.pid}.crt`);
  fs.writeFileSync(tmp, PEM);
  try {
    process.env[CA_PATH_ENV] = tmp;
    const cfg = buildStagingPoolConfig(POOLER);
    assert.equal(cfg.ssl.rejectUnauthorized, true);
    assert.equal(cfg.ssl.ca, PEM);
  } finally {
    if (prev === undefined) delete process.env[CA_PATH_ENV]; else process.env[CA_PATH_ENV] = prev;
    fs.unlinkSync(tmp);
  }
});

test('stagingPgSsl: verified option from the CA path, refuses when missing or not PEM', () => {
  const { stagingPgSsl } = require('./staging_pg_ssl');
  const ca = path.resolve('/ca.crt');
  assert.deepEqual(stagingPgSsl({ env: { [CA_PATH_ENV]: ca }, readFile: reader({ [ca]: PEM }) }), { ca: PEM, rejectUnauthorized: true });
  assert.throws(() => stagingPgSsl({ env: {} }), /is not set/);
  assert.throws(() => stagingPgSsl({ env: { [CA_PATH_ENV]: ca }, readFile: reader({ [ca]: 'x' }) }), /not a PEM/);
});

test('no ops script connects to Postgres with certificate verification disabled', () => {
  const root = path.join(__dirname, '..');
  const bad = [];
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name === 'node_modules' || e.name === 'test') continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.js') && !e.name.endsWith('.test.js')) {
        const src = fs.readFileSync(p, 'utf8');
        src.split('\n').forEach((line, i) => {
          if (/rejectUnauthorized:\s*false/.test(line) && !/^\s*(\*|\/\/)/.test(line)) bad.push(`${path.relative(root, p)}:${i + 1}`);
        });
      }
    }
  };
  walk(root);
  assert.deepEqual(bad, []);
});
