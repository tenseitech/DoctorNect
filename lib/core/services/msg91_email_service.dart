import 'package:flutter/foundation.dart';

import '../enums/user_type.dart';

/// Client stub — MSG91 email credentials and API calls live only in Cloud Functions.
///
/// Do not add auth keys, --dart-define secrets, or HTTP calls to MSG91 here.
abstract final class Msg91EmailService {
  /// Public From address shown in copy only (not a credential).
  static const String fromEmail = 'no-reply@mail.doctornect.com';
  static const String domain = 'mail.doctornect.com';
  static const String fromName = 'DoctorNect';

  /// Template *names* for UI/docs — real DLT template IDs are server env only.
  static const String templateGlobalOtp = 'global_otp';
  static const String templateRegistrationOtp =
      'Registration_OTP_Account_Verification';
  static const String templateForgotPassword = 'forgot_password_46608';
  static const String templateEmailChanges = 'email_changes';
  static const String templateApproved = 'approved_template_';

  /// Client never sends email; Cloud Functions own MSG91 dispatch.
  static const bool emailsEnabled = false;

  static Future<({bool success, String? error, int? statusCode})> sendEmail({
    required String toEmail,
    required String subject,
    required String htmlBody,
    String? recipientName,
    String? plainTextBody,
    String? templateId,
    Map<String, dynamic>? variables,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[Msg91EmailService] Client email disabled. Use Cloud Functions for $toEmail ($subject).',
      );
    }
    return (success: true, error: null, statusCode: 200);
  }

  static Future<({bool success, String? error})> sendOtpEmail({
    required String toEmail,
    required String otpCode,
    String? recipientName,
    String purpose = 'verify your account',
  }) async {
    final result = await sendEmail(
      toEmail: toEmail,
      subject: 'OTP',
      htmlBody: '',
    );
    return (success: result.success, error: result.error);
  }

  static Future<({bool success, String? error})> sendPasswordResetEmail({
    required String toEmail,
    required String otpCode,
    String? recipientName,
  }) async {
    final result = await sendEmail(
      toEmail: toEmail,
      subject: 'Reset password',
      htmlBody: '',
    );
    return (success: result.success, error: result.error);
  }

  static Future<({bool success, String? error})> sendEmailChangeOtpEmail({
    required String toEmail,
    required String otpCode,
    String? recipientName,
  }) async {
    final result = await sendEmail(
      toEmail: toEmail,
      subject: 'Verify email',
      htmlBody: '',
    );
    return (success: result.success, error: result.error);
  }

  static Future<({bool success, String? error})> sendProviderApprovalEmail({
    required String toEmail,
    required String recipientName,
    required UserType providerType,
    String? licenseNumber,
  }) async {
    final result = await sendEmail(
      toEmail: toEmail,
      subject: 'Approved',
      htmlBody: '',
    );
    return (success: result.success, error: result.error);
  }

  static Future<({bool success, String? error})> sendProviderRejectionEmail({
    required String toEmail,
    required String recipientName,
    required UserType providerType,
    required String reason,
  }) async {
    final result = await sendEmail(
      toEmail: toEmail,
      subject: 'Application update',
      htmlBody: '',
    );
    return (success: result.success, error: result.error);
  }
}
