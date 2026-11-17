'use strict';

const { test } = require('node:test');
const assert = require('node:assert');
const {
  parseMajorFromVersionString,
  parseServerRelease,
  serverVersionMatchesProdTarget,
  evaluatePgMajor,
  isLocalReplayPort,
} = require('../lib/pg_version_policy');

test('parseMajorFromVersionString', () => {
  assert.strictEqual(
    parseMajorFromVersionString('PostgreSQL 18.0 on x86_64-pc-linux-gnu'),
    18,
  );
});

test('evaluatePgMajor enforces when requested', () => {
  assert.throws(() => {
    try {
      evaluatePgMajor(
        { versionLine: 'PostgreSQL 17.11' },
        { enforce: true, expectedMajor: 18, label: 'test' },
      );
    } catch (e) {
      assert.strictEqual(e.code, 'PG_MAJOR_MISMATCH');
      throw e;
    }
  });
});

test('serverVersionMatchesProdTarget accepts RDS-style strings', () => {
  assert.strictEqual(
    serverVersionMatchesProdTarget('18.3 (Debian 12.8-1.pgdg120+1)', '18.3'),
    true,
  );
  assert.strictEqual(serverVersionMatchesProdTarget('18.2', '18.3'), false);
});

test('parseServerRelease', () => {
  assert.deepStrictEqual(parseServerRelease('PostgreSQL 18.3 on x86_64'), {
    major: 18,
    minor: 3,
    label: '18.3',
  });
});

test('isLocalReplayPort includes 5440', () => {
  assert.strictEqual(isLocalReplayPort(5440), true);
  assert.strictEqual(isLocalReplayPort(5433), false);
});
