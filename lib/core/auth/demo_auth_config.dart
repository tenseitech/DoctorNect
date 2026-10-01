import 'package:flutter/foundation.dart';

import '../validators/form_validators.dart';
import '../enums/user_type.dart';

/// Demo mode is disabled for production. Firebase Auth is required.
abstract final class DemoAuthConfig {
  static const bool enabled = false;

  /// Demo Super Admin flag: enabled only when dev/demo flag is on (defaults to kDebugMode, false in prod release).
  static const bool enableDemoSuperAdmin = bool.fromEnvironment(
    'ENABLE_DEMO_SUPER_ADMIN',
    defaultValue: kDebugMode,
  );

  static const String demoOtp = '000000';

  static String? validateOtp(String? value) => FormValidators.otp(value);

  static const String demoDoctorPhone = '7666892394';
  static const String demoPatientPhone = '7058809803';
  static const String demoPharmacyPhone = '9359503874';
  static const String demoLabPhone = '9409858233';
  static const String demoAmbulancePhone = '9307583929';
  static const String demoSuperAdminPhone = '9999988888';

  static bool isDemoDoctorPhone(String? phone) {
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoDoctorPhone;
  }

  static bool isDemoPharmacyPhone(String? phone) {
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoPharmacyPhone;
  }

  static bool isDemoLabPhone(String? phone) {
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoLabPhone;
  }

  static bool isDemoAmbulancePhone(String? phone) {
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoAmbulancePhone;
  }

  static bool isDemoPatientPhone(String? phone) {
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoPatientPhone;
  }

  static bool isDemoSuperAdminPhone(String? phone) {
    if (!enableDemoSuperAdmin) return false;
    if (phone == null || phone.isEmpty) return false;
    final digits = FormValidators.mobileDigits(phone) ??
        FormValidators.registrationMobileDigits(phone);
    return digits == demoSuperAdminPhone;
  }

  static bool isDemoRolePhone(UserType role, String? phone) {
    return switch (role) {
      UserType.doctor => isDemoDoctorPhone(phone),
      UserType.patient => isDemoPatientPhone(phone),
      UserType.medicalStore => isDemoPharmacyPhone(phone),
      UserType.lab => isDemoLabPhone(phone),
      UserType.ambulance => isDemoAmbulancePhone(phone),
      UserType.superAdmin => isDemoSuperAdminPhone(phone),
    };
  }

  static bool isAnyDemoPhone(String? phone) {
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

  static String trialLoginHint(UserType role) =>
      'Sign in with the email and password you used during registration.';
}
