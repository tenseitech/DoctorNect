'use strict';

const {
  isRuntimeDocumentDbForbidden,
  assertFirestoreNotForbidden,
} = require('./firestore_forbidden_guard');
const { getLegacyFirestoreDb } = require('./legacy_db');

function createFirestoreForbiddenProxy(caller = 'RuntimeAppDb') {
  const handler = {
    get(_target, prop) {
      if (prop === 'then') return undefined;
      assertFirestoreNotForbidden(`${caller}.${String(prop)}`);
      const nested = () => createFirestoreForbiddenProxy(`${caller}.${String(prop)}`);
      return new Proxy(nested, handler);
    },
    apply() {
      assertFirestoreNotForbidden(`${caller}()`);
      return createFirestoreForbiddenProxy(caller);
    },
  };
  return new Proxy(function runtimeDbForbidden() {}, handler);
}

/**
 * Runtime document DB accessor for callables that accept injected `db`.
 * When forbidden: throws on first .collection() (tests use mocks instead).
 */
function getRuntimeAppDb() {
  if (isRuntimeDocumentDbForbidden()) {
    return createFirestoreForbiddenProxy('getRuntimeAppDb');
  }
  return getLegacyFirestoreDb();
}

module.exports = {
  getRuntimeAppDb,
  createFirestoreForbiddenProxy,
};