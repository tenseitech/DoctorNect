'use strict';

/** Postgres / Redis paths use plain Dates; legacy test mocks accept these shapes. */

function serverTimestamp() {
  return new Date();
}

function timestampFromMs(ms) {
  const d = new Date(ms);
  return {
    toDate: () => d,
    toMillis: () => d.getTime(),
  };
}

function timestampFromDate(date) {
  const d = date instanceof Date ? date : new Date(date);
  return timestampFromMs(d.getTime());
}

/** Drop-in for FieldValue.arrayUnion in legacy mock-db unit tests only. */
const arrayUnion = (...values) => ({ __arrayUnion: values });

/** Drop-in for FieldValue.arrayRemove in legacy mock-db unit tests only. */
const arrayRemove = (...values) => ({ __arrayRemove: values });

function numericIncrement(operand = 1) {
  return { __numericIncrement: operand };
}

module.exports = {
  serverTimestamp,
  timestampFromMs,
  timestampFromDate,
  Timestamp: {
    fromDate: (d) => timestampFromDate(d),
    fromMillis: (ms) => timestampFromMs(ms),
    now: () => timestampFromMs(Date.now()),
  },
  FieldValue: { serverTimestamp, arrayUnion, arrayRemove, increment: numericIncrement },
};