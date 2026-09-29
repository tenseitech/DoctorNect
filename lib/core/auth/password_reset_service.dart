import '../enums/user_type.dart';

/// Handles password-reset operations across roles.
abstract final class PasswordResetService {
  PasswordResetService._();

  static Future<({bool success, String? message})> sendResetEmailForPhone({
    required UserType role,
    required String mobile,
  }) async {
    return (
      success: false,
      message:
          'Email password reset is disabled. Please reset your password directly using Phone SMS OTP verification.',
    );
  }

  static Future<({bool success, String? message})> sendResetEmailForEmail({
    required UserType role,
    required String email,
  }) async {
    return (
      success: false,
      message:
          'Email password reset is disabled. Please reset your password using your registered mobile number and SMS OTP.',
    );
  }
}
