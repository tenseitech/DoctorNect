import '../enums/user_type.dart';
import '../validators/form_validators.dart';
import 'registration_otp_service.dart';

enum ContactVerificationChannel { mobile, email }

/// OTP gate before changing contact details on profile edit (patient, doctor, etc.).
abstract final class ContactChangeOtpService {
  ContactChangeOtpService._();

  static String? _normalizeMobile(String raw) {
    final parsed = FormValidators.parsePhone(raw);
    final err = FormValidators.phoneLocal(parsed.localNumber, dialCode: parsed.dialCode);
    if (err != null) return null;
    return FormValidators.formatFullPhone(parsed.dialCode, parsed.localNumber);
  }

  static String? _normalizeEmail(String raw) {
    final email = raw.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) return null;
    return email;
  }

  static String? _normalize(ContactVerificationChannel channel, String target) {
    return switch (channel) {
      ContactVerificationChannel.mobile => _normalizeMobile(target),
      ContactVerificationChannel.email => _normalizeEmail(target),
    };
  }

  static Future<String?> sendOtp({
    required ContactVerificationChannel channel,
    required String target,
    UserType role = UserType.patient,
  }) async {
    final normalized = _normalize(channel, target);
    if (normalized == null) {
      return switch (channel) {
        ContactVerificationChannel.mobile => 'Enter a valid mobile number',
        ContactVerificationChannel.email => 'Enter a valid email address',
      };
    }

    if (channel == ContactVerificationChannel.email) {
      return 'Email address changes are not allowed.';
    }

    final digits = FormValidators.registrationMobileDigits(target);
    if (digits == null) {
      return 'Enter a valid mobile number';
    }

    final result = await RegistrationOtpService.sendOtp(
      digits,
      role: role,
      otpType: 'contact_change',
    );
    return result.error;
  }

  static Future<String?> verify({
    required ContactVerificationChannel channel,
    required String target,
    required String otp,
    UserType role = UserType.patient,
  }) async {
    final otpError = FormValidators.otp(otp);
    if (otpError != null) return otpError;

    final normalized = _normalize(channel, target);
    if (normalized == null) {
      return switch (channel) {
        ContactVerificationChannel.mobile => 'Enter a valid mobile number',
        ContactVerificationChannel.email => 'Enter a valid email address',
      };
    }

    if (channel == ContactVerificationChannel.email) {
      return 'Email address changes are not allowed.';
    }

    return RegistrationOtpService.verify(
      normalized,
      otp,
      role: role,
      otpType: 'contact_change',
    );
  }

  static String maskTarget(ContactVerificationChannel channel, String target) {
    return switch (channel) {
      ContactVerificationChannel.mobile => _maskMobile(target),
      ContactVerificationChannel.email => _maskEmail(target),
    };
  }

  static String _maskMobile(String raw) {
    final canonical = _normalizeMobile(raw);
    final digits = canonical?.replaceAll(RegExp(r'\D'), '') ??
        raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return raw;
    return '******${digits.substring(digits.length - 4)}';
  }

  static String _maskEmail(String raw) {
    final email = raw.trim();
    final at = email.indexOf('@');
    if (at <= 1) return email;
    final name = email.substring(0, at);
    final domain = email.substring(at);
    final visible = name.length <= 2 ? name[0] : name.substring(0, 2);
    return '$visible***$domain';
  }
}
