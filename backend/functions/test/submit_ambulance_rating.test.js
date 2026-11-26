'use strict';

/**
 * submitAmbulanceRating callable -> submit_ambulance_rating RPC (Postgres path).
 * The fake RPC mirrors the SQL contract in 20261124000003 (single-use per trip, booker only,
 * completed trips only, aggregates updated once). The SQL itself is exercised in db/tests.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const { setDatabaseClientForTesting } = require('../src/db/client');
const { createMemoryPostgrest } = require('./helpers/memory_postgrest');
const { submitAmbulanceRating } = require('../index');

function fakeRatingRpc(args, { table }) {
  const trip = table('ambulance_broadcasts').find((b) => b.broadcast_id === args.p_broadcast_id);
  if (!trip) throw new Error('NOT_FOUND');
  if (trip.patient_id !== args.p_patient_id) throw new Error('FORBIDDEN');
  if (trip.accepted_driver_id !== args.p_ambulance_id) throw new Error('INVALID_ARGUMENT');
  if (trip.status !== 'completed') throw new Error('FAILED_PRECONDITION');
  const ratings = table('ambulance_ratings');
  if (ratings.some((r) => r.broadcast_id === args.p_broadcast_id)) throw new Error('ALREADY_EXISTS');
  ratings.push({ broadcast_id: args.p_broadcast_id, stars: args.p_stars, review: args.p_review });
  const amb = table('ambulances').find((a) => a.ambulance_id === args.p_ambulance_id);
  amb.rating_count += 1;
  amb.rating_sum += args.p_stars;
  return null;
}

function setup() {
  const db = createMemoryPostgrest({
    users: [
      { id: 'pat_uid', firebase_uid: 'pat_uid', role: 'patient', profile_id: 'pat_1' },
      { id: 'other_uid', firebase_uid: 'other_uid', role: 'patient', profile_id: 'pat_2' },
      { id: 'amb_uid', firebase_uid: 'amb_uid', role: 'ambulance', profile_id: 'amb_1' },
    ],
    ambulance_broadcasts: [
      { broadcast_id: 'trip_1', patient_id: 'pat_1', accepted_driver_id: 'amb_1', status: 'completed' },
      { broadcast_id: 'trip_open', patient_id: 'pat_1', accepted_driver_id: 'amb_1', status: 'accepted' },
    ],
    ambulances: [{ ambulance_id: 'amb_1', rating_count: 0, rating_sum: 0 }],
    ambulance_ratings: [],
  }, { rpc: { submit_ambulance_rating: fakeRatingRpc } });
  setDatabaseClientForTesting(db);
  return db;
}

const call = (uid, data) => submitAmbulanceRating.run({ auth: { uid }, app: { appId: 'x' }, data });

test.afterEach(() => setDatabaseClientForTesting(createMemoryPostgrest()));

test('booker rates a completed trip exactly once; aggregates update once', async () => {
  const db = setup();
  const res = await call('pat_uid', { broadcastId: 'trip_1', ambulanceId: 'amb_1', stars: 4, review: 'Fast' });
  assert.equal(res.ok, true);
  await assert.rejects(call('pat_uid', { broadcastId: 'trip_1', ambulanceId: 'amb_1', stars: 1 }), (e) => e.code === 'already-exists');
  assert.equal(db.rows('ambulance_ratings').length, 1);
  assert.deepEqual(db.rows('ambulances')[0], { ambulance_id: 'amb_1', rating_count: 1, rating_sum: 4 });
  const rpcCall = db.calls.find((c) => c.rpc === 'submit_ambulance_rating');
  assert.equal(rpcCall.args.p_patient_id, 'pat_1', 'patient id comes from the server-side profile, not the client');
});

test('another patient, wrong ambulance, open trip and unknown trip are rejected', async () => {
  setup();
  await assert.rejects(call('other_uid', { broadcastId: 'trip_1', ambulanceId: 'amb_1', stars: 5 }), (e) => e.code === 'permission-denied');
  await assert.rejects(call('pat_uid', { broadcastId: 'trip_1', ambulanceId: 'amb_9', stars: 5 }), (e) => e.code === 'invalid-argument');
  await assert.rejects(call('pat_uid', { broadcastId: 'trip_open', ambulanceId: 'amb_1', stars: 5 }), (e) => e.code === 'failed-precondition');
  await assert.rejects(call('pat_uid', { broadcastId: 'nope', ambulanceId: 'amb_1', stars: 5 }), (e) => e.code === 'not-found');
});

test('non patient/doctor roles and bad star values never reach the RPC', async () => {
  const db = setup();
  await assert.rejects(call('amb_uid', { broadcastId: 'trip_1', ambulanceId: 'amb_1', stars: 5 }), (e) => e.code === 'permission-denied');
  await assert.rejects(call('pat_uid', { broadcastId: 'trip_1', ambulanceId: 'amb_1', stars: 9 }), (e) => e.code === 'invalid-argument');
  await assert.rejects(call(undefined, { broadcastId: 'trip_1', ambulanceId: 'amb_1', stars: 5 }));
  assert.equal(db.calls.filter((c) => c.rpc).length, 0);
});
