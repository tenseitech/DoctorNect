import 'package:flutter/foundation.dart';
import 'package:medibond/core/config/firestore_forbidden_guard.dart';

/// Opt-in Firestore SDK for **this test file only**.
///
/// Release builds ignore this (assert fails in debug when simulating release
/// via [FirestoreForbiddenGuard.debugForceReleaseMode]).
@visibleForTesting
void allowFirestoreInThisTestFile() {
  assert(() {
    if (FirestoreForbiddenGuard.debugForceReleaseMode) {
      throw AssertionError(
        'allowFirestoreInThisTestFile must not run under debugForceReleaseMode',
      );
    }
    FirestoreForbiddenGuard.debugOverrideForTesting = false;
    return true;
  }());
}

@visibleForTesting
void resetFirestoreTestAccess() {
  FirestoreForbiddenGuard.debugOverrideForTesting = null;
}
