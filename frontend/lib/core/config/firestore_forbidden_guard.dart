import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Client Firestore SDK is disabled for application data (Postgres-only architecture).
abstract final class FirestoreForbiddenGuard {
  static const String _appEnv =
      String.fromEnvironment('APP_ENV', defaultValue: 'staging');

  static const bool _fromEnv =
      bool.fromEnvironment('FIRESTORE_FORBIDDEN', defaultValue: true);

  @visibleForTesting
  static bool? debugOverride;

  /// When true, simulates release: [debugOverride] must not bypass forbidden.
  @visibleForTesting
  static bool debugForceReleaseMode = false;

  @visibleForTesting
  static set debugOverrideForTesting(bool? value) {
    assert(() {
      if (value != null && value == false && (kReleaseMode || debugForceReleaseMode)) {
        throw AssertionError(
          'FirestoreForbiddenGuard.debugOverride must not disable forbidden in release mode',
        );
      }
      debugOverride = value;
      return true;
    }());
  }

  @visibleForTesting
  static void resetForTesting() {
    debugOverride = null;
    debugForceReleaseMode = false;
  }

  static bool get isForbidden {
    if (debugOverride != null) return debugOverride!;
    if (_fromEnv) return true;
    if (_appEnv == 'production') return true;
    try {
      return Platform.environment['FIRESTORE_FORBIDDEN'] == '1';
    } catch (_) {
      return true;
    }
  }

  static void assertNotForbidden([String? context]) {
    if (isForbidden) {
      throw StateError(
        'FIRESTORE_FORBIDDEN: Client Firestore is disabled; use Supabase/Postgres.'
        '${context != null ? ' ($context)' : ''}',
      );
    }
  }
}
