import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';
import 'operational_log.dart';

/// Mobile crash reporting (Audit 7). Web is not supported by Crashlytics SDK.
abstract final class CrashReporting {
  static bool get isSupported => !kIsWeb;

  static Future<void> configure() async {
    if (!isSupported) return;
    if (!FirebaseBootstrap.isReady) return;

    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);

    final prevFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final safe = _scrub(details.exceptionAsString());
      if (kDebugMode) {
        OperationalLog.error('flutter_fatal', error: safe);
      }
      crashlytics.recordFlutterError(
        details,
        fatal: true,
      );
      prevFlutterOnError?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      final safe = _scrub(error.toString());
      if (kDebugMode) {
        OperationalLog.error('platform_error', error: safe);
      }
      unawaited(
        crashlytics.recordError(error, stack, fatal: true, reason: safe),
      );
      return true;
    };
  }

  static String _scrub(String message) {
    var s = message;
    if (s.contains('Bearer ')) {
      s = s.replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer [REDACTED]');
    }
    if (RegExp(r'^eyJ[\w-]+\.[\w-]+\.[\w-]+$').hasMatch(s)) {
      return '[REDACTED]';
    }
    if (s.length > 300) {
      return '${s.substring(0, 300)}…';
    }
    return s;
  }
}