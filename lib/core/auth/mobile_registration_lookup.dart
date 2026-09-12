import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../enums/user_type.dart';
import '../firebase/firebase_bootstrap.dart';
import '../security/app_check_service.dart';
import '../validators/form_validators.dart';

/// Server-side lookup: which app module owns a mobile number.
class MobileRegistrationLookup {
  MobileRegistrationLookup._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  static Future<({bool found, String? role, String? roleLabel})?> check(
    String mobile,
  ) async {
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
          .call<Map<String, dynamic>>({'mobile': digits});
      final data = Map<String, dynamic>.from(result.data);
      if (data['ok'] != true) return null;
      if (data['found'] != true) {
        return (found: false, role: null, roleLabel: null);
      }
      return (
        found: true,
        role: data['role'] as String?,
        roleLabel: data['roleLabel'] as String?,
      );
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

  /// Popup message when number belongs to another module, or registration blocked.
  static String? conflictMessage({
    required UserType currentRole,
    required bool isRegistration,
    required String registeredRoleLabel,
    String? registeredRole,
  }) {
    final label = registeredRoleLabel.trim().isNotEmpty
        ? registeredRoleLabel.trim()
        : 'another';
    final currentRoleValue = _roleValue(currentRole);
    final sameModule = registeredRole != null && registeredRole == currentRoleValue;

    if (isRegistration) {
      return 'This mobile number is already registered under $label. '
          'Please log in from the $label module or use a different number.';
    }

    if (!sameModule) {
      return 'This mobile number is registered under $label. '
          'Please use the $label login screen.';
    }

    return null;
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
