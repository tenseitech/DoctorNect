'use strict';

/**
 * DoctorNect: Firestore Forbidden Guard
 * 
 * When process.env.FIRESTORE_FORBIDDEN === '1', any attempt to access Firestore
 * in backend/functions throws an immediate Error.
 */

function isFirestoreForbidden() {
  return String(process.env.FIRESTORE_FORBIDDEN || '').trim() === '1';
}

function assertFirestoreNotForbidden(caller) {
  if (isFirestoreForbidden()) {
    const err = new Error(
      `FIRESTORE_FORBIDDEN: Firestore access is blocked under FIRESTORE_FORBIDDEN=1 (${caller || 'unknown'})`
    );
    err.code = 'FIRESTORE_FORBIDDEN';
    throw err;
  }
}

// Hook firebase-admin/firestore
try {
  const adminFirestore = require('firebase-admin/firestore');
  if (adminFirestore && adminFirestore.getFirestore) {
    const originalGetFirestore = adminFirestore.getFirestore;
    adminFirestore.getFirestore = function guardedGetFirestore(...args) {
      assertFirestoreNotForbidden('getFirestore()');
      return originalGetFirestore.apply(this, args);
    };
  }

  if (adminFirestore && adminFirestore.Firestore && adminFirestore.Firestore.prototype) {
    const proto = adminFirestore.Firestore.prototype;
    const methodsToGuard = ['collection', 'doc', 'runTransaction', 'batch', 'getAll', 'listCollections'];
    for (const method of methodsToGuard) {
      if (typeof proto[method] === 'function') {
        const orig = proto[method];
        proto[method] = function guardedMethod(...args) {
          assertFirestoreNotForbidden(`Firestore.prototype.${method}`);
          return orig.apply(this, args);
        };
      }
    }
  }
} catch (_) {}

// Hook firebase-admin
try {
  const admin = require('firebase-admin');
  if (admin && typeof admin.firestore === 'function') {
    const originalAdminFirestore = admin.firestore;
    admin.firestore = function guardedAdminFirestore(...args) {
      assertFirestoreNotForbidden('admin.firestore()');
      return originalAdminFirestore.apply(this, args);
    };
  }
} catch (_) {}

module.exports = {
  isFirestoreForbidden,
  assertFirestoreNotForbidden,
};
