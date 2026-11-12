'use strict';

require('./firestore_forbidden_guard');
const { getFirestore } = require('firebase-admin/firestore');
const { isFirestoreForbidden } = require('./firestore_forbidden_guard');

/**
 * Returns Firestore for legacy/test paths, or null when Postgres-only (FIRESTORE_FORBIDDEN=1).
 * Never call getFirestore() directly in app code — use this helper.
 */
function getLegacyFirestoreDb() {
  if (isFirestoreForbidden()) {
    return null;
  }
  return getFirestore();
}

module.exports = {
  getLegacyFirestoreDb,
};
