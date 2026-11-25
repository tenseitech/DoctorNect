'use strict';

/**
 * Converts the old Firestore-shaped test seed ({ collection: { docId: {camelCaseFields} } })
 * into an in-memory Postgres (PostgREST double) with real table/column names, so suites that
 * were written against the Firestore mock keep their scenarios while exercising the Postgres path.
 *
 *   users/{uid}            -> users { id, firebase_uid, role, profile_id, ... }
 *   lab_bookings/{id}      -> lab_bookings { booking_id, lab_id, patient_id, ... }
 *   ...                    -> camelCase fields become snake_case
 *
 * `_added` mirrors the old mock's audit list: every insert recorded as { collection, data }.
 */
const { createMemoryPostgrest } = require('./memory_postgrest');

const ID_COLUMN = {
  patients: 'patient_id',
  doctors: 'doctor_id',
  lab_bookings: 'booking_id',
  lab_orders: 'order_id',
  health_records: 'record_id',
  prescriptions: 'prescription_id',
  pharmacy_deliveries: 'delivery_id',
  appointments: 'appointment_id',
  medical_stores: 'store_id',
  labs: 'lab_id',
  ambulances: 'ambulance_id',
  promoted_ads: 'ad_id',
  referrals: 'referral_id',
};

const snake = (k) => k.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);

function rowFrom(collection, docId, data) {
  const row = {};
  for (const [k, v] of Object.entries(data || {})) row[snake(k)] = v;
  if (collection === 'users') {
    row.id = row.id || docId;
    row.firebase_uid = row.firebase_uid || docId;
  } else {
    const idCol = ID_COLUMN[collection] || 'id';
    row[idCol] = row[idCol] || docId;
  }
  return row;
}

function createPgFromLegacySeed(initial = {}, options = {}) {
  const tables = {};
  for (const [collection, docs] of Object.entries(initial)) {
    tables[collection] = Object.entries(docs || {}).map(([id, data]) => rowFrom(collection, id, data));
  }
  const pg = createMemoryPostgrest(tables, options);
  Object.defineProperty(pg, '_added', {
    get() {
      return pg.calls
        .filter((c) => c.mode === 'insert')
        .flatMap((c) => (Array.isArray(c.payload) ? c.payload : [c.payload]).map((data) => ({ collection: c.table, data })));
    },
  });
  return pg;
}

module.exports = { createPgFromLegacySeed, rowFrom, ID_COLUMN };
