import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../enums/user_type.dart';
import '../firebase/firebase_bootstrap.dart';
import '../security/app_check_service.dart';
import '../validators/form_validators.dart';

enum MobileLookupIntent { login, registration }

/// Server-side lookup: whether a mobile number conflicts with the current flow.
class MobileRegistrationLookup {
  MobileRegistrationLookup._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  static const loginConflictMessage =
      'This mobile number may be registered under a different account type. '
      'Try another login option or contact support.';

  static const registrationConflictMessage =
      'This mobile number may already be registered. '
      'Try logging in, or use a different number.';

  /// Returns `true` when the number conflicts, `false` when clear, `null` on skip/error.
  static Future<bool?> check(
    String mobile, {
    required UserType role,
    required MobileLookupIntent intent,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;

    final appCheckBlock = await AppCheckService.ensureForCallable();
    if (appCheckBlock != null) {
      if (kDebugMode) {
        debugPrint('[MobileRegistrationLookup] App Check blocked: $appCheckBlock');
      }
      return null;
    }

    final digits = FormValidators.registrationMobileDigits(mobile) ??
        FormValidators.mobileDigits(mobile);
    if (digits == null || digits.length != 10) return null;

    try {
      final result = await _functions
          .httpsCallable('lookupMobileRegistration')
          .call<Map<String, dynamic>>({
        'mobile': digits,
        'role': _roleValue(role),
        'intent': intent == MobileLookupIntent.login ? 'login' : 'registration',
      });
      final data = Map<String, dynamic>.from(result.data);
      if (data['ok'] != true) return null;
      return data['conflict'] == true;
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[MobileRegistrationLookup] ${e.code}: ${e.message}',
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MobileRegistrationLookup] $e');
      }
      return null;
    }
  }

  static String _roleValue(UserType role) => switch (role) {
        UserType.superAdmin => 'super_admin',
        UserType.doctor => 'doctor',
        UserType.patient => 'patient',
        UserType.medicalStore => 'medicalStore',
        UserType.lab => 'lab',
        UserType.ambulance => 'ambulance',
      };
}
