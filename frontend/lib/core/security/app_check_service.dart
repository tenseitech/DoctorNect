import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../firebase/firebase_bootstrap.dart';

/// Best-effort App Check token warm-up before Cloud Function calls.
///
/// Does not block OTP — the server decides via ENFORCE_OTP_APP_CHECK. When
/// enforcement is off, callables work without a token; when on, Play Integrity /
/// reCAPTCHA must be configured.
abstract final class AppCheckService {
  static bool _warmUpAttempted = false;
  static bool _warmUpSucceeded = false;
  static String? _setupHint;
  static String? _lastFailureReason;

  /// True when this device obtained an App Check token in this app session.
  static bool get hasToken => _warmUpSucceeded;

  /// Non-sensitive reason code for the last token failure (never contains a
  /// token or device id). One of: `attestation_failed`, `rate_limited`,
  /// `play_integrity_unavailable`, `network`, `token_unavailable`.
  static String? get lastFailureReason => _lastFailureReason;

  @visibleForTesting
  static void debugSetState({required bool hasToken, String? failureReason}) {
    _warmUpAttempted = true;
    _warmUpSucceeded = hasToken;
    _lastFailureReason = failureReason;
  }

  @visibleForTesting
  static String classifyFailure(Object error) {
    final err = error.toString().toLowerCase();
    if (err.contains('too many attempts')) return 'rate_limited';
    if (err.contains('403') || err.contains('attestation failed')) {
      return 'attestation_failed';
    }
    if (err.contains('integrity') ||
        err.contains('play services') ||
        err.contains('api_not_available')) {
      return 'play_integrity_unavailable';
    }
    if (err.contains('network') ||
        err.contains('timeout') ||
        err.contains('unreachable')) {
      return 'network';
    }
    return 'token_unavailable';
  }

  /// Warms App Check during startup. Safe to call multiple times when successful.
  static Future<bool> warmUp({bool forceRefresh = false}) async {
    if (!FirebaseBootstrap.isReady) return false;
    if (_warmUpSucceeded && !forceRefresh) return true;

    try {
      final token = await FirebaseAppCheck.instance.getToken(forceRefresh);
      if (token != null && token.isNotEmpty) {
        FirebaseBootstrap.appCheckReady = true;
        _warmUpSucceeded = true;
        _setupHint = null;
        _lastFailureReason = null;
        if (kDebugMode) {
          debugPrint('App Check token ready (${token.length} chars).');
        }
        return true;
      }
    } catch (e, st) {
      _setupHint = _buildSetupHint(e);
      _lastFailureReason = classifyFailure(e);
      // Reason code only: safe to log in release builds.
      debugPrint('[AppCheck] token_failed reason=$_lastFailureReason');
      if (kDebugMode) {
        debugPrint('App Check getToken failed: $e\n$st');
        if (_setupHint != null) debugPrint(_setupHint!);
      }
    }

    FirebaseBootstrap.appCheckReady = false;
    _warmUpSucceeded = false;
    return false;
  }

  /// Attaches an App Check token when possible; never blocks the callable.
  static Future<String?> ensureForCallable() async {
    if (!FirebaseBootstrap.isReady) {
      return 'Firebase is not available.';
    }

    if (!_warmUpAttempted ||
        (!_warmUpSucceeded && !FirebaseBootstrap.appCheckReady)) {
      _warmUpAttempted = true;
      await warmUp();
    }

    return null;
  }

  static String _buildSetupHint(Object error) {
    final err = error.toString();
    final configured = AppConstants.resolvedAppCheckDebugToken;
    final attestationFailed =
        err.contains('403') || err.toLowerCase().contains('attestation failed');
    final rateLimited = err.toLowerCase().contains('too many attempts');

    if (configured.isNotEmpty && attestationFailed) {
      return 'App Check rejected the configured APP_CHECK_DEBUG_TOKEN. Register it in '
          'Firebase Console → App Check → Android/iOS app → Manage debug tokens, '
          'then fully restart the app (not hot reload).';
    }

    if (configured.isNotEmpty) {
      return 'App Check is using APP_CHECK_DEBUG_TOKEN. If OTP still fails, '
          'confirm that token is registered under Firebase Console → App Check '
          '→ Manage debug tokens.';
    }

    if (rateLimited) {
      return 'App Check rate-limited this device after repeated failures. '
          'Fully stop the app, register the debug token (see logcat line containing '
          '"debug secret"), wait one minute, then restart.\n'
          'Easier: generate a UUID, register it in Firebase Console → App Check → '
          'Manage debug tokens, and run:\n'
          'flutter run --dart-define=APP_CHECK_DEBUG_TOKEN=your-uuid';
    }

    if (attestationFailed) {
      return 'App Check debug token is not registered yet (403 attestation failed).\n'
          '1. In Android Studio Logcat, filter for "DebugAppCheckProvider" or '
          '"debug secret" and copy the UUID.\n'
          '2. Firebase Console → App Check → com.tenseitech.doctornect → '
          'Manage debug tokens → Add token.\n'
          '3. Fully restart the app (stop flutter run, then run again).\n'
          'Or pre-register a UUID and run:\n'
          'flutter run --dart-define=APP_CHECK_DEBUG_TOKEN=your-uuid';
    }

    return 'App Check token unavailable on this device. For local/release testing, '
        'register a debug token in Firebase Console → App Check, or pass '
        '--dart-define=APP_CHECK_DEBUG_TOKEN=your-uuid';
  }
}
