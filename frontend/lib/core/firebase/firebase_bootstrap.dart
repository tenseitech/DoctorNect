import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../constants/app_constants.dart';
import '../security/app_check_provider_policy.dart';
import '../security/app_check_service.dart';
import '../storage/storage_feature_flag.dart';
import '../validation/server_validation_service.dart';
import 'firebase_error_messages.dart';

/// Initializes Firebase before the app runs.
abstract final class FirebaseBootstrap {
  static bool isReady = false;
  static bool appCheckReady = false;
  static String? lastInitError;

  static Future<bool>? _initFuture;

  @visibleForTesting
  static void resetForTesting() {
    _initFuture = null;
    isReady = false;
    appCheckReady = false;
    lastInitError = null;
  }

  static Future<void> activateAppCheck() => _activateAppCheck();

  /// Idempotent, concurrent-safe Firebase startup (native auto-init + Dart).
  static Future<bool> initialize() {
    if (isReady) return SynchronousFuture(true);
    final existing = _initFuture;
    if (existing != null) return existing;
    _initFuture = _initializeOnce();
    return _initFuture!;
  }

  static Future<bool> _initializeOnce() async {
    try {
      lastInitError = null;

      if (Firebase.apps.isNotEmpty) {
        await _onFirebaseAppReady();
        return true;
      }

      if (!DefaultFirebaseOptions.isConfigured) {
        isReady = false;
        lastInitError = 'Firebase API keys not configured.';
        return false;
      }

      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } on FirebaseException catch (e) {
        if (e.code == 'duplicate-app' || Firebase.apps.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
              'Firebase.initializeApp: ${e.code} — using existing [DEFAULT] app',
            );
          }
        } else {
          rethrow;
        }
      }

      if (Firebase.apps.isEmpty) {
        isReady = false;
        lastInitError =
            'Could not start Firebase. Please restart the app and try again.';
        return false;
      }

      await _onFirebaseAppReady();
      return true;
    } catch (e, st) {
      isReady = false;
      if (Firebase.apps.isNotEmpty) {
        // Another caller or native layer won the race; treat as ready.
        await _onFirebaseAppReady();
        return true;
      }
      lastInitError = describeUserFacingError(
        e,
        fallback:
            'Could not connect to Firebase. Check your network and try again.',
      );
      if (kDebugMode) {
        debugPrint('Firebase init failed: $e\n$st');
      }
      return false;
    } finally {
      _initFuture = null;
    }
  }

  static Future<void> _onFirebaseAppReady() async {
    if (isReady) return;
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }
    isReady = true;
    if (kDebugMode) {
      debugPrint('Firebase ready (${defaultTargetPlatform.name})');
    }
    unawaited(activateAppCheck());
    unawaited(_loadValidationRules());
    unawaited(StorageFeatureFlag.initialize());
  }
}

Future<void> _activateAppCheck() async {
  FirebaseBootstrap.appCheckReady = false;
  try {
    if (kIsWeb) {
      final siteKey = AppConstants.resolvedAppCheckRecaptchaSiteKey;
      if (siteKey.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            'App Check skipped on web: set RECAPTCHA_SITE_KEY dart-define after registering App Check.',
          );
        }
        return;
      }
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaV3Provider(siteKey),
      );
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
      try {
        final token = await FirebaseAppCheck.instance.getToken();
        if (token != null && token.isNotEmpty) {
          FirebaseBootstrap.appCheckReady = true;
          if (kDebugMode) {
            debugPrint('App Check activated on web (reCAPTCHA v3).');
          }
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('App Check web token failed: $e\n$st');
        }
      }
      return;
    }

    // Release builds use Play Integrity when installed from Play Store.
    // The debug provider is only for `flutter run` and explicit staging test
    // builds (APP_ENV=staging + APP_CHECK_DEBUG_PROVIDER=true); see
    // AppCheckProviderPolicy and docs/APP_CHECK_SETUP.md. Production never.
    final useDebugProvider =
        AppCheckProviderPolicy.current() == AppCheckProviderKind.debug;
    final debugToken =
        useDebugProvider ? AppConstants.resolvedAppCheckDebugToken : '';
    debugPrint(
      useDebugProvider
          ? '[AppCheck] provider=debug (not for production)'
          : '[AppCheck] provider=platform_attestation',
    );
    await FirebaseAppCheck.instance.activate(
      providerAndroid: useDebugProvider
          ? AndroidDebugProvider(
              debugToken: debugToken.isEmpty ? null : debugToken,
            )
          : const AndroidPlayIntegrityProvider(),
      providerApple: useDebugProvider
          ? AppleDebugProvider(
              debugToken: debugToken.isEmpty ? null : debugToken,
            )
          : const AppleDeviceCheckProvider(),
    );
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    if (useDebugProvider && debugToken.isNotEmpty) {
      debugPrint(
        'App Check using a fixed APP_CHECK_DEBUG_TOKEN. Register it in '
        'Firebase Console → App Check → Manage debug tokens if not done yet.',
      );
    } else if (useDebugProvider) {
      debugPrint(
        'App Check debug provider: copy the "debug secret" printed by '
        'DebugAppCheckProvider in logcat and register it in Firebase Console.',
      );
    }

    // Try once at startup; avoid repeated getToken calls (Firebase rate-limits).
    final ready = await AppCheckService.warmUp();
    if (kDebugMode) {
      debugPrint(
        ready
            ? 'App Check activated on mobile.'
            : 'App Check activated on mobile but token fetch failed — see logs above.',
      );
    }
  } catch (e, st) {
    FirebaseBootstrap.appCheckReady = false;
    if (kDebugMode) {
      debugPrint('App Check activation failed: $e\n$st');
    }
  }
}

Future<void> _loadValidationRules() async {
  try {
    await ServerValidationService.loadRules();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('Validation rules preload failed: $e\n$st');
    }
  }
}

/// Legacy alias used by older imports.
Future<bool> initializeFirebase() => FirebaseBootstrap.initialize();
