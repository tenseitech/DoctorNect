import '../validators/form_validators.dart';
import '../enums/user_type.dart';

/// Demo mode is disabled for production. Firebase Auth is required.
abstract final class DemoAuthConfig {
  static const bool enabled = false;

  static String? validateOtp(String? value) => FormValidators.otp(value);

  static String trialLoginHint(UserType role) =>
      'Sign in with the email and password you used during registration.';
}
