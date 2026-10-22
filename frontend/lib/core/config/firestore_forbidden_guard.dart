import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Guard to enforce FIRESTORE_FORBIDDEN test mode in Flutter.
///
/// When active, any Firestore operation or repository access throws immediately.
abstract final class FirestoreForbiddenGuard {
  static const bool _fromEnv =
      bool.fromEnvironment('FIRESTORE_FORBIDDEN', defaultValue: false);

  @visibleForTesting
  static bool? debugOverride;

  static bool get isForbidden {
    if (debugOverride != null) return debugOverride!;
    if (_fromEnv) return true;
    try {
      return Platform.environment['FIRESTORE_FORBIDDEN'] == '1';
    } catch (_) {
      return false;
    }
  }

  static void assertNotForbidden([String? context]) {
    if (isForbidden) {
      throw StateError(
        'FIRESTORE_FORBIDDEN: Firestore access is blocked under FIRESTORE_FORBIDDEN=1'
        '${context != null ? ' ($context)' : ''}',
      );
    }
  }
}
