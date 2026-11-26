'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const {
  readFirebaseHostingCsp,
  assertConnectSrcCoversRequiredOrigins,
  assertConnectSrcNotWildcarded,
} = require('../../../scripts/lib/hosting_csp');

const repoRoot = path.join(__dirname, '..', '..', '..');

test('hosting connect-src does not use blanket https:/wss: wildcards (SEC-07)', () => {
  const csp = readFirebaseHostingCsp(repoRoot);
  const check = assertConnectSrcNotWildcarded(csp);
  assert.equal(check.ok, true, `Forbidden wildcards in connect-src: ${check.bad.join(', ')}`);
});

test('hosting connect-src covers required Flutter Web / Firebase origins (SEC-07)', () => {
  const csp = readFirebaseHostingCsp(repoRoot);
  const check = assertConnectSrcCoversRequiredOrigins(csp);
  assert.equal(
    check.ok,
    true,
    `connect-src missing required origins: ${check.missing.join(', ')}`,
  );
});