import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';

/// Central feature flag manager for AWS S3 Storage rollout.
///
/// Default value is strictly `false` (all existing Firebase Storage paths run unchanged).
/// Can be enabled via:
/// 1. Firebase Remote Config parameter: `use_s3_storage = true`
/// 2. Compile-time flag: `--dart-define=USE_S3_STORAGE=true`
/// 3. In-memory override for testing: `StorageFeatureFlag.debugOverride = true`
abstract final class StorageFeatureFlag {
  static const String flagKey = 'use_s3_storage';

  static const String _envOverride = String.fromEnvironment('USE_S3_STORAGE');

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
        debugPrint('[StorageFeatureFlag] Remote config init warning: $e');
      }
    }
  }

  /// Whether S3 storage is enabled for uploads. Defaults strictly to `false`.
  static bool get useS3Storage {
    if (debugOverride != null) return debugOverride!;

    if (_envOverride.isNotEmpty) {
      return _envOverride.toLowerCase() == 'true';
    }

    if (!FirebaseBootstrap.isReady) return false;

    try {
      return FirebaseRemoteConfig.instance.getBool(flagKey);
    } catch (_) {
      return false;
    }
  }
}
