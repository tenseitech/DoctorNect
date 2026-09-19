import '../enums/user_type.dart';
import '../validators/form_validators.dart';
import 'mobile_registration_lookup.dart';

/// Whether OTP should establish an existing session (login) or a new profile (register).
enum UnifiedAuthPath {
  login,
  register,

  /// Mobile is registered under a different role — block and show support message.
  blockedWrongRole,
}

/// Resolves login vs register from server-side mobile lookup (no separate Register UI).
abstract final class UnifiedAuthCoordinator {
  static const wrongRoleMessage =
      'This mobile number may be registered under a different account type. '
      'Try another login option or contact support.';

  /// Uses [lookupMobileRegistration]: registration conflict => account exists;
  /// login conflict => same mobile but different role.
  static Future<UnifiedAuthPath> resolvePath({
    required String mobile,
    required UserType role,
  }) async {
    final digits = FormValidators.registrationMobileDigits(mobile) ??
        FormValidators.mobileDigits(mobile);
    if (digits == null || digits.length != 10) {
      return UnifiedAuthPath.register;
    }

    final registrationConflict = await MobileRegistrationLookup.check(
      digits,
      role: role,
      intent: MobileLookupIntent.registration,
    );
    if (registrationConflict != true) {
      return UnifiedAuthPath.register;
    }

    final loginConflict = await MobileRegistrationLookup.check(
      digits,
      role: role,
      intent: MobileLookupIntent.login,
    );
    if (loginConflict == true) {
      return UnifiedAuthPath.blockedWrongRole;
    }

    return UnifiedAuthPath.login;
  }

  static String otpTypeForPath(UnifiedAuthPath path) =>
      path == UnifiedAuthPath.login ? 'login' : 'registration';

  static String roleLabel(UserType role) => switch (role) {
        UserType.superAdmin => 'Super Admin',
        UserType.doctor => 'Doctor',
        UserType.patient => 'Patient',
        UserType.medicalStore => 'Pharmacy',
        UserType.lab => 'Lab',
        UserType.ambulance => 'Ambulance',
      };

  static String roleSubtitle(UserType role) => switch (role) {
        UserType.doctor => 'Manage appointments, patients & prescriptions',
        UserType.patient => 'Book doctors, labs & track your health',
        UserType.medicalStore => 'Receive and dispense prescriptions',
        UserType.lab => 'Manage diagnostic test orders',
        UserType.ambulance => 'Handle emergency pickup requests',
        _ => 'Sign in to continue',
      };
}
