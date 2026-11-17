'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  buildHarnessSeedSteps,
  listHarnessSeedTables,
  assertHarnessSeedSteps,
} = require('../lib/harness_seed_sql');

test('harness seed steps list all fixture tables', () => {
  const steps = buildHarnessSeedSteps({
    pA: 'a',
    pB: 'b',
    docA: 'd1',
    docB: 'd2',
    storeA: 's1',
    storeB: 's2',
    labA: 'l1',
    labB: 'l2',
    ambA: 'm1',
    ambB: 'm2',
    apptId: 'ap',
    hrId: 'hr',
    bcId: 'bc',
    bcPendingId: 'bcp',
    bcCancelledId: 'bcc',
    reqId: 'rq',
    reqPendingId: 'rqp',
    delId: 'del',
    labBkId: 'lb',
    labOrdId: 'lo',
  });
  const audit = assertHarnessSeedSteps(steps);
  assert.equal(audit.stepCount, 4);
  const tables = listHarnessSeedTables(steps);
  assert.ok(tables.includes('public.ambulance_trip_contacts'));
  assert.ok(tables.includes('public.ambulance_broadcasts'));
});