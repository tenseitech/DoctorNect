/// MSG91 OTP helpers — SMS send/verify runs only on Cloud Functions.
///
/// This client stub exists so older call sites compile. It never holds
/// MSG91 auth keys and never talks to MSG91 directly.
abstract final class Msg91OtpService {
  /// Normalizes mobile to include country code (default 91 for India).
  static String formatMobileForMsg91(String rawDigits, {String dialCode = '91'}) {
    final clean = rawDigits.replaceAll(RegExp(r'\D'), '');
    final cleanDial = dialCode.replaceAll(RegExp(r'\D'), '');
    if (clean.startsWith(cleanDial)) return clean;
    if (clean.length == 10) return '$cleanDial$clean';
    return clean;
  }

  static Future<bool> retrySmsOtp(String mobileDigits, {String retryType = 'text'}) async {
    return false;
  }

  static Future<({bool success, String? error, String? debugOtp})> sendOtp({
    required String identifier,
    Object? role,
    String otpType = 'registration',
    String? templateId,
  }) async {
    return (
      success: false,
      error:
          'Direct MSG91 access is disabled. OTP must be sent through Cloud Functions.',
      debugOtp: null,
    );
  }

  static Future<({bool success, String? error, String? sessionId})> verifyOtp({
    required String identifier,
    required String otp,
    Object? role,
  }) async {
    return (
      success: false,
      error:
          'Direct MSG91 access is disabled. OTP must be verified through Cloud Functions.',
      sessionId: null,
    );
  }
}
