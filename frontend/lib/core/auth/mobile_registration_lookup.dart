import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../enums/user_type.dart';
import '../firebase/firebase_bootstrap.dart';
import '../security/app_check_service.dart';
import '../validators/form_validators.dart';

enum MobileLookupIntent { login, registration }

/// Typed result from server-side mobile registration lookup.
class MobileLookupResult {
  final bool exists;
  final UserType? role;
  final String? rawRole;
  final bool? conflict;
  final String? errorMessage;

  const MobileLookupResult({
    required this.exists,
    this.role,
    this.rawRole,
    this.conflict,
    this.errorMessage,
  });

  bool get isError => errorMessage != null;
  bool get isFound => !isError && exists;
  bool get isNotFound => !isError && !exists;
}

/// Server-side lookup: whether a mobile number conflicts with the current flow
/// or maps to an existing registered user.
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

  /// Parses server role string to [UserType].
  static UserType? parseUserType(String? raw) {
    if (raw == null) return null;
    final lower = raw.trim().toLowerCase();
    return switch (lower) {
      'doctor' => UserType.doctor,
      'patient' => UserType.patient,
      'medical' ||
      'medicalstore' ||
      'medical_store' ||
      'pharmacy' =>
        UserType.medicalStore,
      'lab' => UserType.lab,
      'ambulance' => UserType.ambulance,
      'superadmin' || 'super_admin' => UserType.superAdmin,
      _ => null,
    };
  }

  /// Authoritative server-side lookup. Returns [MobileLookupResult] distinguishing
  /// between error (`isError`), found (`isFound` / `role`), and not found (`isNotFound`).
  static Future<MobileLookupResult> lookup(
    String mobile, {
    MobileLookupIntent intent = MobileLookupIntent.login,
    UserType? role,
  }) async {
    final digits = FormValidators.registrationMobileDigits(mobile) ??
        FormValidators.mobileDigits(mobile);
    if (digits == null || digits.length != 10) {
      return const MobileLookupResult(
        exists: false,
        errorMessage: 'Enter a valid 10-digit mobile number.',
      );
    }

    if (!FirebaseBootstrap.isReady) {
      return const MobileLookupResult(
        exists: false,
        errorMessage: 'Service temporarily unavailable. Please try again.',
      );
    }

    final appCheckBlock = await AppCheckService.ensureForCallable();
    if (appCheckBlock != null) {
      if (kDebugMode) {
        debugPrint(
          '[MobileRegistrationLookup] App Check blocked: $appCheckBlock',
        );
      }
      return MobileLookupResult(
        exists: false,
        errorMessage: appCheckBlock,
      );
    }

    try {
      final payload = <String, dynamic>{
        'mobile': digits,
        'intent': intent == MobileLookupIntent.login ? 'login' : 'registration',
      };
      if (role != null) {
        payload['role'] = _roleValue(role);
      }

      final result = await _functions
          .httpsCallable('lookupMobileRegistration')
          .call<Map<String, dynamic>>(payload);
      final data = Map<String, dynamic>.from(result.data);
      if (data['ok'] != true) {
        return const MobileLookupResult(
          exists: false,
          errorMessage: 'Could not verify account registration status.',
        );
      }

      final exists = data['exists'] == true;
      final rawRole = data['role'] as String?;
      final resolvedRole = parseUserType(rawRole);
      final conflict = data['conflict'] == true;

      return MobileLookupResult(
        exists: exists,
        role: resolvedRole,
        rawRole: rawRole,
        conflict: conflict,
      );
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('[MobileRegistrationLookup] ${e.code}: ${e.message}');
      }
      return MobileLookupResult(
        exists: false,
        errorMessage: e.message ?? 'Server error checking account.',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MobileRegistrationLookup] $e');
      }
      return const MobileLookupResult(
        exists: false,
        errorMessage: 'Network error checking account. Please try again.',
      );
    }
  }

  /// Returns `true` when the number conflicts, `false` when clear, `null` on skip/error.
  static Future<bool?> check(
    String mobile, {
    required UserType role,
    required MobileLookupIntent intent,
  }) async {
    final res = await lookup(mobile, intent: intent, role: role);
    if (res.isError) return null;
    return res.conflict;
  }

  static String _roleValue(UserType role) => switch (role) {
        UserType.superAdmin => 'super_admin',
        UserType.doctor => 'doctor',
        UserType.patient => 'patient',
        UserType.medicalStore || UserType.medical => 'medicalStore',
        UserType.lab => 'lab',
        UserType.ambulance => 'ambulance',
      };
}
