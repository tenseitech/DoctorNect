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

  static const lookupUnavailableMessage =
      'Could not verify account status. Check your connection and try again.';

  static UserType? parseUserType(String? raw) {
    if (raw == null) return null;
    final lower = raw.trim().toLowerCase();
    return switch (lower) {
      'doctor' => UserType.doctor,
      'patient' => UserType.patient,
      'medical' || 'medicalstore' || 'medical_store' || 'pharmacy' =>
        UserType.medicalStore,
      'lab' => UserType.lab,
      'ambulance' => UserType.ambulance,
      'superadmin' || 'super_admin' => UserType.superAdmin,
      _ => null,
    };
  }

  /// Pre-OTP lookup via [lookupMobileRegistration]. Falls back to [check] when
  /// the backend omits `exists` / `role` (legacy conflict-only contract).
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
        errorMessage: lookupUnavailableMessage,
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
          errorMessage: lookupUnavailableMessage,
        );
      }

      if (!data.containsKey('exists')) {
        return await _lookupFromLegacyConflictChecks(
          digits,
          intent: intent,
          role: role,
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
        errorMessage: e.message ?? lookupUnavailableMessage,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MobileRegistrationLookup] $e');
      }
      return const MobileLookupResult(
        exists: false,
        errorMessage: lookupUnavailableMessage,
      );
    }
  }

  static Future<MobileLookupResult> _lookupFromLegacyConflictChecks(
    String digits, {
    required MobileLookupIntent intent,
    UserType? role,
  }) async {
    if (role == null) {
      return const MobileLookupResult(
        exists: false,
        errorMessage: lookupUnavailableMessage,
      );
    }

    final registrationConflict = await _fetchConflictOnly(
      digits,
      role: role,
      intent: MobileLookupIntent.registration,
    );
    if (registrationConflict == null) {
      return const MobileLookupResult(
        exists: false,
        errorMessage: lookupUnavailableMessage,
      );
    }
    if (registrationConflict != true) {
      return const MobileLookupResult(exists: false, conflict: false);
    }

    final loginConflict = await _fetchConflictOnly(
      digits,
      role: role,
      intent: MobileLookupIntent.login,
    );
    if (loginConflict == null) {
      return const MobileLookupResult(
        exists: false,
        errorMessage: lookupUnavailableMessage,
      );
    }
    if (loginConflict == true) {
      return MobileLookupResult(
        exists: true,
        role: role,
        conflict: true,
      );
    }

    return MobileLookupResult(
      exists: true,
      role: role,
      conflict: false,
    );
  }

  /// Returns `true` when the number conflicts, `false` when clear, `null` on skip/error.
  static Future<bool?> check(
    String mobile, {
    required UserType role,
    required MobileLookupIntent intent,
  }) async {
    final res = await lookup(mobile, intent: intent, role: role);
    if (res.isError) return null;
    if (res.conflict != null) return res.conflict;
    if (res.isNotFound) return false;
    if (res.isFound) return false;
    return null;
  }

  static Future<bool?> _fetchConflictOnly(
    String digits, {
    required UserType role,
    required MobileLookupIntent intent,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;

    final appCheckBlock = await AppCheckService.ensureForCallable();
    if (appCheckBlock != null) return null;

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
    } on FirebaseFunctionsException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
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
