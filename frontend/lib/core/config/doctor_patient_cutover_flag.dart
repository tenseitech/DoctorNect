import 'package:flutter/foundation.dart';

/// Postgres is the only application data store. This flag remains for tests only.
abstract final class DoctorPatientCutoverFlag {
  @visibleForTesting
  static bool? debugOverride;

  /// Always `true` in production builds. Tests may set [debugOverride] to false.
  static bool get isEnabled => debugOverride ?? true;

  /// No-op: Remote Config cutover removed (Postgres-only).
  static Future<void> initialize() async {}

  @visibleForTesting
  static void resetForTesting() {
    debugOverride = null;
  }
}
