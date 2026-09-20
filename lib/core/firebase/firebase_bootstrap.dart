import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../constants/app_constants.dart';
import '../security/app_check_service.dart';
import '../validation/server_validation_service.dart';
import 'firebase_error_messages.dart';

/// Initializes Firebase before the app runs.
abstract final class FirebaseBootstrap {
  static bool isReady = false;
  static bool appCheckReady = false;
  static String? lastInitError;

  static Future<bool> initialize() async {
    if (isReady) return true;
    try {
      lastInitError = null;
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (_) {}
      await _activateAppCheck();
      isReady = true;
      if (kDebugMode) {
        debugPrint('Firebase initialized (${defaultTargetPlatform.name})');
      }
      // Load validation rules from Cloud Functions (non-blocking).
      unawaited(_loadValidationRules());
      return true;
    } catch (e, st) {
      isReady = false;
      lastInitError = describeUserFacingError(
        e,
        fallback:
            'Could not connect to Firebase. Refresh the page or use Chrome.',
      );
      if (kDebugMode) {
        debugPrint('Firebase init failed: $e\n$st');
      }
      return false;
    }
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
    // Pass --dart-define=APP_CHECK_DEBUG_TOKEN=uuid for sideloaded release testing.
    final debugToken = AppConstants.resolvedAppCheckDebugToken;
    final useDebugProvider = kDebugMode || debugToken.isNotEmpty;
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

    if (kDebugMode && debugToken.isNotEmpty) {
      debugPrint(
        'App Check using APP_CHECK_DEBUG_TOKEN. Register "$debugToken" in '
        'Firebase Console → App Check → Manage debug tokens if not done yet.',
      );
    } else if (!kDebugMode && debugToken.isNotEmpty) {
      debugPrint(
        'Release build using APP_CHECK_DEBUG_TOKEN for App Check (local testing only).',
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
