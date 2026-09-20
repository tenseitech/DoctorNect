import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/country_phone_codes.dart';
import '../enums/user_type.dart';
import '../firebase/firebase_bootstrap.dart';
import '../firebase/firebase_error_messages.dart';
import '../security/app_check_service.dart';
import '../security/client_request_throttle.dart';
import '../validators/form_validators.dart';

/// Registration / login / reset OTP via Cloud Functions only.
/// MSG91 credentials never leave the server.
class RegistrationOtpService {
  RegistrationOtpService._();

  static const _serviceUnavailable =
      'OTP service temporarily unavailable. Please try again shortly.';

  static String? _verificationSessionId;
  static String? _loginCustomToken;

  static String? get verificationSessionId => _verificationSessionId;
  static String? get loginCustomToken => _loginCustomToken;

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  static Future<({String? error, String? debugOtp})> sendOtp(
    String identifier, {
    UserType role = UserType.patient,
    String otpType = 'registration',
  }) async {
    final trimmed = identifier.trim();
    final isEmail = trimmed.contains('@');
    String? digits;
    if (!isEmail) {
      digits = FormValidators.registrationMobileDigits(trimmed);
      if (digits == null) {
        return (
          error: FormValidators.phoneLocal(
                trimmed,
                dialCode: CountryPhoneCodes.defaultDialCode,
              ) ??
              'Invalid mobile number format.',
          debugOtp: null,
        );
      }
    } else {
      return (
        error:
            'Email OTP is disabled. Please use your 10-digit mobile number for phone verification.',
        debugOtp: null,
      );
    }

    if (!FirebaseBootstrap.isReady) {
      return (error: 'Firebase is not available.', debugOtp: null);
    }

    final appCheckBlock = await AppCheckService.ensureForCallable();
    if (appCheckBlock != null) {
      if (kDebugMode) {
        debugPrint(
            '[RegistrationOtpService] App Check blocked send: $appCheckBlock');
      }
      return (error: appCheckBlock, debugOtp: null);
    }

    try {
      final throttle = ClientRequestThrottle.denyMessage(
        'otp_send',
        max: 8,
        window: const Duration(minutes: 15),
        message: 'Too many OTP requests. Please wait and try again.',
      );
      if (throttle != null) {
        return (error: throttle, debugOtp: null);
      }
      final payload = <String, dynamic>{
        'role': _roleValue(role),
        'otpType': otpType,
        'mobile': digits,
      };
      if (kDebugMode) {
        debugPrint(
          '[RegistrationOtpService] sendUserRegistrationOtp '
          'region=asia-south1 otpType=$otpType mobile=******${digits.substring(digits.length - 4)} '
          'appCheckReady=${FirebaseBootstrap.appCheckReady}',
        );
      }
      final result = await _functions
          .httpsCallable('sendUserRegistrationOtp')
          .call<Map<String, dynamic>>(payload);
      final data = Map<String, dynamic>.from(result.data);
      if (kDebugMode) {
        debugPrint(
          '[RegistrationOtpService] send ok=${data['ok']} '
          'expiresIn=${data['expiresInSeconds']}',
        );
      }
      if (data['ok'] == true) {
        final debugOtp = kDebugMode ? data['debugOtp'] as String? : null;
        return (error: null, debugOtp: debugOtp);
      }
      return (error: 'Could not send OTP. Please try again.', debugOtp: null);
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[RegistrationOtpService] send error: ${e.code} - ${e.message} '
          'details=${e.details}',
        );
      }
      return (error: _mapFunctionsError(e), debugOtp: null);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RegistrationOtpService] send error: $e');
      }
      return (
        error: 'Could not send OTP. Please check your network and try again.',
        debugOtp: null,
      );
    }
  }

  /// Returns null when OTP is valid. Sets [verificationSessionId] / [loginCustomToken].
  static Future<String?> verify(
    String identifier,
    String otp, {
    UserType role = UserType.patient,
    String otpType = 'registration',
  }) async {
    final otpError = FormValidators.otp(otp);
    if (otpError != null) return otpError;

    final trimmed = identifier.trim();
    if (trimmed.contains('@')) {
      return 'Email verification is disabled. Please verify via mobile SMS OTP.';
    }
    final digits = FormValidators.registrationMobileDigits(trimmed);
    if (digits == null) {
      return FormValidators.phoneLocal(
        trimmed,
        dialCode: CountryPhoneCodes.defaultDialCode,
      );
    }

    if (!FirebaseBootstrap.isReady) {
      return 'Firebase is not available.';
    }

    await AppCheckService.ensureForCallable();

    try {
      final payload = <String, dynamic>{
        'role': _roleValue(role),
        'otp': otp.trim(),
        'mobile': digits,
        'otpType': otpType,
      };
      final result = await _functions
          .httpsCallable('verifyUserRegistrationOtp')
          .call<Map<String, dynamic>>(payload);
      final data = Map<String, dynamic>.from(result.data);
      if (data['ok'] == true) {
        final sessionId = data['sessionId'] as String?;
        _verificationSessionId =
            sessionId != null && sessionId.isNotEmpty ? sessionId : null;
        final token = data['customToken'] as String?;
        _loginCustomToken = token != null && token.isNotEmpty ? token : null;
        return null;
      }
      return 'Invalid or expired OTP. Please try again.';
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[RegistrationOtpService] verify error: ${e.code} - ${e.message}');
      }
      return _mapFunctionsError(e);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RegistrationOtpService] verify error: $e');
      }
      return 'Invalid or expired OTP. Please try again.';
    }
  }

  /// Completes phone OTP login by minting a Firebase custom token server-side.
  static Future<({String? error, String? customToken})> completeMobileLogin({
    required String mobile,
    required String sessionId,
    required UserType role,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return (error: 'Firebase is not available.', customToken: null);
    }
    final digits = FormValidators.registrationMobileDigits(mobile) ??
        FormValidators.mobileDigits(mobile);
    if (digits == null || digits.isEmpty) {
      return (
        error: 'Enter a valid 10-digit mobile number.',
        customToken: null
      );
    }
    if (sessionId.isEmpty) {
      return (error: 'OTP verification session is missing.', customToken: null);
    }

    await AppCheckService.ensureForCallable();

    // Prefer token already returned by verify when otpType=login.
    if (_loginCustomToken != null && _loginCustomToken!.isNotEmpty) {
      final token = _loginCustomToken;
      return (error: null, customToken: token);
    }

    try {
      final result = await _functions
          .httpsCallable('completeMobileOtpLogin')
          .call<Map<String, dynamic>>({
        'mobile': digits,
        'sessionId': sessionId,
        'role': _roleValue(role),
      });
      final data = Map<String, dynamic>.from(result.data);
      final token = data['customToken'] as String?;
      if (data['ok'] == true && token != null && token.isNotEmpty) {
        _loginCustomToken = token;
        return (error: null, customToken: token);
      }
      return (error: 'Could not complete mobile login.', customToken: null);
    } on FirebaseFunctionsException catch (e) {
      return (error: _mapFunctionsError(e), customToken: null);
    } catch (e) {
      return (
        error: describeUserFacingError(e,
            fallback: 'Could not complete mobile login.'),
        customToken: null,
      );
    }
  }

  static Future<({bool success, String? message})> resetPasswordWithOtp({
    required String identifier,
    required String sessionId,
    required String newPassword,
    required UserType role,
  }) async {
    if (sessionId.isEmpty) {
      return (success: false, message: 'OTP verification session is missing.');
    }
    final passwordError = FormValidators.password(newPassword);
    if (passwordError != null) {
      return (success: false, message: passwordError);
    }

    if (!FirebaseBootstrap.isReady) {
      return (success: false, message: 'Firebase is not available.');
    }

    try {
      final result = await _functions
          .httpsCallable('resetUserPasswordWithOtp')
          .call<Map<String, dynamic>>({
        'identifier': identifier.trim(),
        'sessionId': sessionId,
        'newPassword': newPassword,
        'role': _roleValue(role),
      });
      final data = Map<String, dynamic>.from(result.data);
      if (data['ok'] == true || data['success'] == true) {
        clearVerificationSession();
        return (
          success: true,
          message:
              data['message'] as String? ?? 'Password updated successfully!',
        );
      }
      return (
        success: false,
        message: data['message'] as String? ?? 'Failed to update password.',
      );
    } on FirebaseFunctionsException catch (e) {
      return (success: false, message: _mapFunctionsError(e));
    } catch (e) {
      return (
        success: false,
        message:
            describeUserFacingError(e, fallback: 'Failed to update password.'),
      );
    }
  }

  /// Applies a pre-registration OTP session after Firebase Auth signup.
  static Future<String?> finalizePatientVerification(String sessionId) async {
    if (sessionId.isEmpty) {
      return 'Mobile OTP verification is required.';
    }
    if (!FirebaseBootstrap.isReady) {
      return 'Firebase is not available.';
    }
    if (FirebaseAuth.instance.currentUser == null) {
      return 'Sign-in required to finalize verification.';
    }

    try {
      final result = await _functions
          .httpsCallable('finalizePatientOtpVerification')
          .call<Map<String, dynamic>>({'sessionId': sessionId});
      final data = Map<String, dynamic>.from(result.data);
      if (data['ok'] == true &&
          (data['mobileVerified'] == true || data['verified'] == true)) {
        clearVerificationSession();
        return null;
      }
      return 'Could not finalize mobile verification.';
    } on FirebaseFunctionsException catch (e) {
      return _mapFunctionsError(e);
    } catch (e) {
      return describeUserFacingError(
        e,
        fallback: 'Could not finalize mobile verification.',
      );
    }
  }

  static void clearVerificationSession() {
    _verificationSessionId = null;
    _loginCustomToken = null;
  }

  static void clearPending(String mobile, {UserType? role}) {
    clearVerificationSession();
  }

  /// Local-only sessions are no longer accepted in production paths.
  static bool isLocalVerificationSession(String? sessionId) => false;

  /// Applies a pre-registration OTP session after Firebase Auth signup.
  static Future<String?> finalizeRegistrationVerification(String sessionId) =>
      finalizePatientVerification(sessionId);

  static String _roleValue(UserType role) => switch (role) {
        UserType.superAdmin => 'super_admin',
        UserType.doctor => 'doctor',
        UserType.patient => 'patient',
        UserType.medicalStore => 'medicalStore',
        UserType.lab => 'lab',
        UserType.ambulance => 'ambulance',
      };

  static String mapCallableError(FirebaseFunctionsException e) =>
      _mapFunctionsError(e);

  static String _cleanFunctionsMessage(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll(RegExp(r'\s*\[\d+\]\s*$'), '').trim();
  }

  static String _mapFunctionsError(FirebaseFunctionsException e) {
    if (_isAppCheckRejection(e)) {
      if (kIsWeb) {
        return kDebugMode
            ? 'App Check rejected this request. Configure reCAPTCHA for web: '
                '--dart-define=RECAPTCHA_SITE_KEY=your_key and register localhost '
                'in Firebase App Check + reCAPTCHA admin.'
            : 'Security verification failed. Please use the official mobile app.';
      }
      return kDebugMode
          ? 'App Check rejected this OTP request. Register the debug token from '
              'device logs in Firebase Console → App Check, then restart the app.'
          : 'Security verification failed. Update the app and try again.';
    }

    final rawMessage = _cleanFunctionsMessage(e.message);
    return switch (e.code) {
      'already-exists' => rawMessage.isNotEmpty
          ? rawMessage
          : 'This mobile number is already registered under another account.',
      'not-found' => rawMessage.isNotEmpty
          ? rawMessage
          : 'No account found for this mobile number. Please register first.',
      'failed-precondition' => _failedPreconditionMessage(rawMessage),
      'deadline-exceeded' => 'OTP expired. Send a new one.',
      'permission-denied' => 'Incorrect OTP. Check the code and try again.',
      'resource-exhausted' => _resourceExhaustedMessage(rawMessage),
      'invalid-argument' =>
        rawMessage.isNotEmpty ? rawMessage : 'Invalid OTP request.',
      'unavailable' => rawMessage.isNotEmpty
          ? rawMessage
          : 'SMS service is temporarily unavailable. Please try again shortly.',
      'internal' || 'unknown' => _serviceUnavailable,
      _ => rawMessage.isNotEmpty ? rawMessage : _serviceUnavailable,
    };
  }

  static String _failedPreconditionMessage(String rawMessage) {
    final lower = rawMessage.toLowerCase();
    if (lower.contains('send otp first') || lower.contains('otp session expired')) {
      return 'OTP expired. Send a new one.';
    }
    if (rawMessage.isNotEmpty) return rawMessage;
    return 'Mobile number is registered under a different account.';
  }

  static String _resourceExhaustedMessage(String rawMessage) {
    final lower = rawMessage.toLowerCase();
    if (lower.contains('invalid attempt') || lower.contains('too many invalid')) {
      return 'Too many wrong attempts. Send a new OTP.';
    }
    if (lower.contains('wait a minute') || lower.contains('wait and try')) {
      return rawMessage.isNotEmpty
          ? rawMessage
          : 'Too many OTP requests. Please wait and try again.';
    }
    if (rawMessage.isNotEmpty) return rawMessage;
    return 'Too many attempts. Wait and try again.';
  }

  static bool _isAppCheckRejection(FirebaseFunctionsException e) {
    final code = e.code.toLowerCase();
    final message = e.message?.toLowerCase() ?? '';
    if (message.contains('app check') ||
        message.contains('app attestation') ||
        message.contains('app attestation failed') ||
        message.contains('debug token') ||
        message.contains('play integrity') ||
        message.contains('devicecheck')) {
      return true;
    }
    // Callable App Check enforcement often returns code unauthenticated + "Unauthenticated".
    if (code == 'unauthenticated' &&
        (message.isEmpty || message == 'unauthenticated')) {
      return true;
    }
    return (code == 'failed-precondition' || code == 'unauthenticated') &&
        message.contains('integrity');
  }
}
