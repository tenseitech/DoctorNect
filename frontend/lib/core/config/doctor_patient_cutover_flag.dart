import 'dart:async';

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
/// IAM ROLES & SECURITY:
/// - Backend Cloud Functions / Admin SDK requires: `roles/firebaseremoteconfig.viewer`
///   (or `roles/firebaseremoteconfig.admin` for template mutation).
/// - Mobile Client: standard Firebase Authentication + App Check token.
///
/// ROLLBACK PLAN:
/// If any issue arises during or after cutover:
/// 1. Set Firebase Remote Config `use_supabase_db_doctor_patient = false` in Firebase Console.
/// 2. Client immediately switches back to Firestore repositories on the next fetch/restart
///    or real-time `onConfigUpdated` event with zero binary redeployment and zero downtime.
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
  static StreamSubscription<RemoteConfigUpdate>? _updateSub;

  /// Optional listener for observability / monitoring when Remote Config falls back.
  static void Function(String alertMessage)? onFallbackAlert;

  /// Initializes Remote Config defaults, activates values, and listens for live updates.
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

      // Listen for real-time config updates pushed from Firebase Console
      _updateSub?.cancel();
      _updateSub = remoteConfig.onConfigUpdated.listen(
        (event) async {
          if (event.updatedKeys.contains(flagKey)) {
            await remoteConfig.activate();
            if (kDebugMode) {
              debugPrint(
                '[DoctorPatientCutoverFlag] Real-time Remote Config activated. isEnabled=$isEnabled',
              );
            }
          }
        },
        onError: (e) {
          _triggerFallbackAlert('Remote Config live update stream failed: $e');
        },
      );

      _initialized = true;
    } catch (e) {
      _triggerFallbackAlert(
        'Remote Config initialization failed ($e); falling back to compile-time or default (false)',
      );
      if (kDebugMode) {
        debugPrint('[DoctorPatientCutoverFlag] Remote config init warning: $e');
      }
    }
  }

  static void _triggerFallbackAlert(String message) {
    if (kDebugMode) {
      debugPrint('[DoctorPatientCutoverFlag ALERT] $message');
    }
    onFallbackAlert?.call(message);
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
    } catch (e) {
      _triggerFallbackAlert('Failed reading Remote Config key "$flagKey": $e');
      return false;
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    debugOverride = null;
    _initialized = false;
    _updateSub?.cancel();
    _updateSub = null;
    onFallbackAlert = null;
  }
}
