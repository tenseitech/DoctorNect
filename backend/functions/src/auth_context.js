'use strict';

const { AsyncLocalStorage } = require('node:async_hooks');

/**
 * Per-request verified Firebase auth (uid + decoded ID token claims) for the duration of one
 * callable invocation. Filled only by callable_with_auth_context.js from request.auth, which
 * firebase-functions populates after verifying the ID token: never from request data.
 */
const storage = new AsyncLocalStorage();

function runWithAuth(auth, fn) {
  const value = auth && auth.uid ? { uid: String(auth.uid), token: auth.token || {} } : null;
  return storage.run(value, fn);
}

/** @returns {{ uid: string, token: object } | null} */
function currentAuth() {
  return storage.getStore() || null;
}

module.exports = { runWithAuth, currentAuth };
