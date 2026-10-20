import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';

/// Central runtime feature flag manager for Doctor & Patient Supabase Database Cutover.
///
/// SCOPE & DESIGN:
/// - Single global flag (all-or-nothing cutover, NOT percentage rollout).
/// - Default value is strictly `false` (all existing Firestore paths run unchanged).
/// - Dual-write sync triggers in Cloud Functions must stay ON until production data
///   migration is verified to avoid data loss.
///
/// ROLLBACK PLAN:
/// If any issue arises during or after cutover:
/// 1. Set Firebase Remote Config `use_supabase_db_doctor_patient = false` in Firebase Console.
/// 2. Client immediately switches back to Firestore repositories on the next fetch/restart
///    with zero binary redeployment and zero downtime.
///
/// ACTIVATION:
/// 1. Firebase Remote Config parameter: `use_supabase_db_doctor_patient = true`
/// 2. Compile-time flag: `--dart-define=USE_SUPABASE_DB_DOCTOR_PATIENT=true`
/// 3. In-memory override for testing: `DoctorPatientCutoverFlag.debugOverride = true`
abstract final class DoctorPatientCutoverFlag {
  static const String flagKey = 'use_supabase_db_doctor_patient';

  static const String _envOverride =
      String.fromEnvironment('USE_SUPABASE_DB_DOCTOR_PATIENT');

  @visibleForTesting
  static bool? debugOverride;

  static bool _initialized = false;

  /// Initializes Remote Config defaults (non-blocking).
  static Future<void> initialize() async {
    if (_initialized || !FirebaseBootstrap.isReady) return;

    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode
              ? const Duration(seconds: 0)
              : const Duration(hours: 1),
        ),
      );
      await remoteConfig.setDefaults({
        flagKey: false,
      });

      // Best-effort fetch & activate in background
      await remoteConfig.fetchAndActivate();
      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DoctorPatientCutoverFlag] Remote config init warning: $e');
      }
    }
  }

  /// Whether Supabase repositories should be used for Doctor & Patient data.
  /// Defaults strictly to `false` until cutover is validated.
  static bool get isEnabled {
    if (debugOverride != null) return debugOverride!;

    if (_envOverride.isNotEmpty) {
      return _envOverride.trim().toLowerCase() == 'true';
    }

    if (!FirebaseBootstrap.isReady || !_initialized) {
      return false;
    }

    try {
      return FirebaseRemoteConfig.instance.getBool(flagKey);
    } catch (_) {
      return false;
    }
  }
}
