import 'package:flutter/foundation.dart';

/// Ambulance module visibility. Default **false** in release builds until product/SQL are aligned.
///
/// Override at compile time: `--dart-define=AMBULANCE_ENABLED=true`
abstract final class AmbulanceEnabled {
  static const String _env =
      String.fromEnvironment('AMBULANCE_ENABLED', defaultValue: 'false');

  @visibleForTesting
  static bool? debugOverride;

  /// In release: only `AMBULANCE_ENABLED=true` enables ambulance. In debug/profile: defaults to true for dev.
  static bool get isOn {
    if (debugOverride != null) return debugOverride!;
    if (kReleaseMode) {
      final v = _env.trim().toLowerCase();
      return v == '1' || v == 'true' || v == 'yes';
    }
    return true;
  }

  @visibleForTesting
  static void resetForTesting() => debugOverride = null;
}
