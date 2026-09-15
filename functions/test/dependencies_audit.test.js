'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const functionsDir = path.join(__dirname, '..');

function readPackageJson() {
  return JSON.parse(fs.readFileSync(path.join(functionsDir, 'package.json'), 'utf8'));
}

function readLockVersion(packageName) {
  const lock = JSON.parse(fs.readFileSync(path.join(functionsDir, 'package-lock.json'), 'utf8'));
  const entry = lock.packages[`node_modules/${packageName}`];
  assert.ok(entry, `Missing lock entry for ${packageName}`);
  return entry.version;
}

function parseSemver(version) {
  const match = String(version).match(/^(\d+)\.(\d+)\.(\d+)/);
  assert.ok(match, `Invalid semver: ${version}`);
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
  };
}

function assertAtLeast(version, minimum) {
  const current = parseSemver(version);
  const floor = parseSemver(minimum);
  const ordered =
    current.major - floor.major
    || current.minor - floor.minor
    || current.patch - floor.patch;
  assert.ok(ordered >= 0, `${version} is below required minimum ${minimum}`);
}

test('functions package pins patched firebase-admin and firebase-functions releases', () => {
  const pkg = readPackageJson();
  assert.match(pkg.dependencies['firebase-admin'], /14\.4\.0/);
  assert.match(pkg.dependencies['firebase-functions'], /7\.3\.2/);
  assert.equal(pkg.engines.node, '22');
  assertAtLeast(readLockVersion('firebase-admin'), '14.4.0');
  assertAtLeast(readLockVersion('firebase-functions'), '7.3.2');
});

test('npm audit reports no moderate or higher vulnerabilities', () => {
  const npmCmd = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  const output = execFileSync(npmCmd, ['audit', '--json'], {
    cwd: functionsDir,
    encoding: 'utf8',
    shell: process.platform === 'win32',
    env: {
      ...process.env,
      npm_config_devdir: undefined,
    },
  });

  const report = JSON.parse(output);
  const vulnerabilities = Object.values(report.vulnerabilities || {});
  const blocked = vulnerabilities.filter((entry) => {
    return entry.severity === 'moderate'
      || entry.severity === 'high'
      || entry.severity === 'critical';
  });
  assert.equal(
    blocked.length,
    0,
    `Unexpected vulnerabilities: ${blocked.map((entry) => entry.name).join(', ')}`,
  );
});

test('firebase-admin modular APIs used by functions still load after upgrade', () => {
  const { initializeApp } = require('firebase-admin/app');
  const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
  const { getAuth } = require('firebase-admin/auth');
  const { getMessaging } = require('firebase-admin/messaging');
  const { getAppCheck } = require('firebase-admin/app-check');

  assert.equal(typeof initializeApp, 'function');
  assert.equal(typeof getFirestore, 'function');
  assert.equal(typeof FieldValue.serverTimestamp, 'function');
  assert.equal(typeof Timestamp.now, 'function');
  assert.equal(typeof getAuth, 'function');
  assert.equal(typeof getMessaging, 'function');
  assert.equal(typeof getAppCheck, 'function');
});
