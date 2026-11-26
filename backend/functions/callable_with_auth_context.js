'use strict';

const https = require('firebase-functions/v2/https');
const { runWithAuth } = require('./src/auth_context');

/**
 * Drop-in for firebase-functions/v2/https onCall: runs the handler inside the verified-auth
 * context so data-plane routing (src/db/request_plane.js) can read the caller's server-set claims.
 */
function onCall(optsOrHandler, maybeHandler) {
  if (typeof optsOrHandler === 'function') {
    return https.onCall((request) => runWithAuth(request.auth, () => optsOrHandler(request)));
  }
  return https.onCall(optsOrHandler, (request) => runWithAuth(request.auth, () => maybeHandler(request)));
}

module.exports = { onCall, onRequest: https.onRequest, HttpsError: https.HttpsError };
