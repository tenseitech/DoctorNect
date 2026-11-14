'use strict';

const { test } = require('node:test');
const assert = require('node:assert');

test('rds_scratch_replay module loads without ReferenceError', () => {
  let mod;
  assert.doesNotThrow(() => {
    mod = require('../db/rds_scratch_replay');
  });
  assert.equal(typeof mod.runRdsScratchReplay, 'function');
  assert.equal(typeof mod.isRdsReplayTargetHost, 'function');
});

test('isRdsReplayTargetHost resolves PROD_RDS_HOST via getHostFingerprint', () => {
  const { isRdsReplayTargetHost } = require('../db/rds_scratch_replay');
  assert.equal(
    isRdsReplayTargetHost('127.0.0.1', 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com'),
    false,
  );
  assert.equal(
    isRdsReplayTargetHost(
      'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com',
      'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com',
    ),
    true,
  );
  assert.equal(isRdsReplayTargetHost('scratch.rds.amazonaws.com', ''), true);
});