import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';

/// Client-side hook that records auth outcomes through existing Cloud Functions.
/// Server emits structured security logs (no raw passwords / OTP codes).
abstract final class SecurityTelemetry {
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Call after a successful email/password sign-in (clears failure counters + logs).
  static Future<void> recordLoginSuccess(String identifier) async {
    if (!FirebaseBootstrap.isReady) return;
    final id = identifier.trim().toLowerCase();
    if (id.isEmpty) return;
    try {
      await _functions.httpsCallable('clearFailedLogins').call({'identifier': id});
    } catch (e) {
      if (kDebugMode) debugPrint('[SecurityTelemetry] recordLoginSuccess: $e');
    }
  }

  /// Call after Firebase Auth rejects credentials.
  static Future<void> recordLoginFailure(String identifier) async {
    if (!FirebaseBootstrap.isReady) return;
    final id = identifier.trim().toLowerCase();
    if (id.isEmpty) return;
    try {
      await _functions.httpsCallable('recordFailedLogin').call({'identifier': id});
    } catch (e) {
      if (kDebugMode) debugPrint('[SecurityTelemetry] recordLoginFailure: $e');
    }
  }
}
