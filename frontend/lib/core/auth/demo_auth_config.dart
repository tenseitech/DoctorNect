import 'package:flutter/foundation.dart';

import '../validators/form_validators.dart';
import '../enums/user_type.dart';

/// Demo mode is disabled for production. Firebase Auth is required.
abstract final class DemoAuthConfig {
  static const bool enabled = bool.fromEnvironment(
    'ENABLE_DEMO_AUTH',
    defaultValue: false,
  );

  /// Compile-time safety guard evaluated at build time.
  static const DemoAuthReleaseGuard buildTimeGuard = DemoAuthReleaseGuard();

  /// Runtime verification called during main() initialization.
  static void verifyReleaseBuildSafety() {
    // Reference const build-time guard
    const _ = buildTimeGuard;
    if (kReleaseMode && (enabled || enableDemoSuperAdmin)) {
      throw StateError(
        'CRITICAL SECURITY ERROR: Demo auth configuration detected in release mode. '
        'Release builds must never include demo auth config.',
      );
    }
  }

  /// Demo Super Admin flag: enabled only when dev/demo flag is on (defaults to kDebugMode, false in prod release).
  static const bool enableDemoSuperAdmin = bool.fromEnvironment(
    'ENABLE_DEMO_SUPER_ADMIN',
    defaultValue: kDebugMode,
  );

  static const String demoOtp = '000000';

  static String? validateOtp(String? value) => FormValidators.otp(value);

  /// Injectable flag for testing release mode behavior.
  /// When true, acts as if running under kReleaseMode.
  @visibleForTesting
  static bool? debugReleaseModeOverride;

  /// Returns true only when demo mode is allowed (disabled in release builds).
  static bool get isDemoAllowed {
    final isRelease = debugReleaseModeOverride ?? kReleaseMode;
    if (isRelease) return false;
    return enabled || kDebugMode;
  }

  static const String demoDoctorPhone = '9999900002';
  static const String demoPatientPhone = '9999900001';
  static const String demoPharmacyPhone = '9999900003';
  static const String demoLabPhone = '9999900004';
  static const String demoAmbulancePhone = '9999900005';
  static const String demoSuperAdminPhone = '9999988888';

  static bool isDemoDoctorPhone(String? phone) {
    if (!isDemoAllowed) return false;
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoDoctorPhone;
  }

  static bool isDemoPharmacyPhone(String? phone) {
    if (!isDemoAllowed) return false;
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoPharmacyPhone;
  }

  static bool isDemoLabPhone(String? phone) {
    if (!isDemoAllowed) return false;
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoLabPhone;
  }

  static bool isDemoAmbulancePhone(String? phone) {
    if (!isDemoAllowed) return false;
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoAmbulancePhone;
  }

  static bool isDemoPatientPhone(String? phone) {
    if (!isDemoAllowed) return false;
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoPatientPhone;
  }

  static bool isDemoSuperAdminPhone(String? phone) {
    if (!isDemoAllowed || !enableDemoSuperAdmin) return false;
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoSuperAdminPhone;
  }

  /// Safely checks if a profile document ID matches a demo doctor ID.
  /// Strictly requires [isDemoAllowed] and exact match (or standard 'd_' prefix).
  static bool isDemoDoctorId(String? docId) {
    if (!isDemoAllowed) return false;
    if (docId == null || docId.isEmpty) return false;
    final trimmed = docId.trim();
    return trimmed == demoDoctorPhone ||
        trimmed == 'd_$demoDoctorPhone' ||
        trimmed == '+91$demoDoctorPhone';
  }

  static bool isDemoPharmacyId(String? storeId) {
    if (!isDemoAllowed) return false;
    if (storeId == null || storeId.isEmpty) return false;
    final trimmed = storeId.trim();
    return trimmed == demoPharmacyPhone ||
        trimmed == 'm_$demoPharmacyPhone' ||
        trimmed == '+91$demoPharmacyPhone';
  }

  static bool isDemoLabId(String? labId) {
    if (!isDemoAllowed) return false;
    if (labId == null || labId.isEmpty) return false;
    final trimmed = labId.trim();
    return trimmed == demoLabPhone ||
        trimmed == 'l_$demoLabPhone' ||
        trimmed == '+91$demoLabPhone';
  }

  static bool isDemoAmbulanceId(String? ambId) {
    if (!isDemoAllowed) return false;
    if (ambId == null || ambId.isEmpty) return false;
    final trimmed = ambId.trim();
    return trimmed == demoAmbulancePhone ||
        trimmed == 'a_$demoAmbulancePhone' ||
        trimmed == '+91$demoAmbulancePhone';
  }

  static bool isDemoRolePhone(UserType role, String? phone) {
    return switch (role) {
      UserType.doctor => isDemoDoctorPhone(phone),
      UserType.patient => isDemoPatientPhone(phone),
      UserType.medicalStore || UserType.medical => isDemoPharmacyPhone(phone),
      UserType.lab => isDemoLabPhone(phone),
      UserType.ambulance => isDemoAmbulancePhone(phone),
      UserType.superAdmin => isDemoSuperAdminPhone(phone),
    };
  }

  static bool isAnyDemoPhone(String? phone) {
    if (!isDemoAllowed) return false;
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoDoctorPhone ||
        digits == demoPharmacyPhone ||
        digits == demoLabPhone ||
        digits == demoAmbulancePhone ||
        digits == demoPatientPhone ||
        (enableDemoSuperAdmin && digits == demoSuperAdminPhone);
  }

  static UserType? roleForDemoPhone(String? phone) {
    if (!isDemoAllowed) return null;
    if (phone == null || phone.isEmpty) return null;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    if (digits == demoDoctorPhone) return UserType.doctor;
    if (digits == demoPatientPhone) return UserType.patient;
    if (digits == demoPharmacyPhone) return UserType.medicalStore;
    if (digits == demoLabPhone) return UserType.lab;
    if (digits == demoAmbulancePhone) return UserType.ambulance;
    if (enableDemoSuperAdmin && digits == demoSuperAdminPhone) {
      return UserType.superAdmin;
    }
    return null;
  }

  static String trialLoginHint(UserType role) =>
      'Sign in with the email and password you used during registration.';
}

/// Compile-time guard: In release mode, const constructor assert fails build
/// if demo authentication or demo super admin is enabled.
class DemoAuthReleaseGuard {
  const DemoAuthReleaseGuard()
      : assert(
          !kReleaseMode ||
              (!DemoAuthConfig.enabled && !DemoAuthConfig.enableDemoSuperAdmin),
          'FATAL: Demo auth is strictly prohibited in release builds! '
          'Ensure DemoAuthConfig.enabled and ENABLE_DEMO_SUPER_ADMIN are false.',
        );
}
