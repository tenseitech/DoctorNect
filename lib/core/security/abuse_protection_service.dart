import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';

/// Client helpers for server-side abuse / bot protection callables.
///
/// Server limits in Cloud Functions are the source of truth; this layer
/// invokes the gates and maps rate-limit errors to user-facing messages.
abstract final class AbuseProtectionService {
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Call before [FirebaseAuth.createUserWithEmailAndPassword].
  static Future<String?> assertAccountCreationAllowed({
    String? email,
    String? mobile,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;
    final cleanEmail = email?.trim().toLowerCase() ?? '';
    final cleanMobile = mobile?.trim() ?? '';
    if (cleanEmail.isEmpty && cleanMobile.isEmpty) return null;

    try {
      await _functions.httpsCallable('assertAccountCreationAllowed').call({
        if (cleanEmail.isNotEmpty) 'email': cleanEmail,
        if (cleanMobile.isNotEmpty) 'mobile': cleanMobile,
        'identifier': cleanEmail.isNotEmpty ? cleanEmail : cleanMobile,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Too many account creation attempts. Please try again later.';
      }
      if (e.code == 'failed-precondition') {
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'App integrity check required. Update the app and try again.';
      }
      return e.message?.trim().isNotEmpty == true
          ? e.message!
          : 'Could not verify account creation. Please try again.';
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            'AbuseProtectionService.assertAccountCreationAllowed: $e\n$st');
      }
      // Fail open only when the gate is unreachable (network); server still
      // rate-limits registration OTP and other signup callables.
      return null;
    }
  }

  /// Call before generative / LLM features (not needed for validateVitalAdvisory,
  /// which already consumes the AI abuse bucket server-side).
  static Future<String?> consumeAiGenerationQuota({
    String feature = 'general',
  }) async {
    if (!FirebaseBootstrap.isReady) return null;
    try {
      await _functions.httpsCallable('consumeAiGenerationQuota').call({
        'feature': feature,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'AI generation rate limit exceeded. Please try again later.';
      }
      if (kDebugMode) {
        debugPrint(
          'AbuseProtectionService.consumeAiGenerationQuota: ${e.code} ${e.message}',
        );
      }
      return null;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AbuseProtectionService.consumeAiGenerationQuota: $e\n$st');
      }
      return null;
    }
  }
}
