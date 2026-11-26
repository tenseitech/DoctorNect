import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/dashboard/dashboard_shell.dart';
import '../../features/ambulance/data/ambulance_login_cache.dart';
import '../../features/ambulance/data/ambulance_store.dart';
import '../constants/app_constants.dart';
import '../enums/user_type.dart';
import '../firebase/ambulance_auth_helper.dart';
import '../firebase/firebase_auth_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../firebase/firebase_error_messages.dart';
import '../firebase/repositories/ambulance_repository.dart';
import '../config/ambulance_enabled.dart';
import '../notifications/app_toast.dart';
import '../session/ambulance_session.dart';
import '../session/app_session.dart';
import '../validators/form_validators.dart';
import '../validators/name_validator.dart';
import 'registration_otp_service.dart';
import 'unified_auth_coordinator.dart';
import 'unified_auth_navigation.dart';
import '../../features/onboarding/onboarding_name_screen.dart';
import '../../features/welcome/welcome_screen.dart';

enum UnifiedAuthStep { mobile, otp }

/// Mobile → OTP → login/register flow, owned by whichever surface renders it.
///
/// Both the full-screen mobile auth screen and the inline desktop auth card
/// drive this, so the Firebase/OTP calls and the login-vs-register branch exist
/// in exactly one place. Callers own the text field, the OTP widget and the
/// layout; this only owns the flow state and the network calls.
/// Role to sign in with after a verified OTP for an EXISTING account: only the role the
/// server returned. Null (unknown/missing) means "do not sign in" (never default to patient).
UserType? loginRoleFromServer(UserType? serverRole) => serverRole;

class UnifiedAuthFlowController extends ChangeNotifier {
  UnifiedAuthFlowController({this.role});

  final UserType? role;

  UnifiedAuthStep _step = UnifiedAuthStep.mobile;
  UnifiedAuthPath? _authPath;
  UserType? _matchedRole;
  String? _mobileDigits;
  String _otp = '';
  bool _sendingOtp = false;
  bool _verifying = false;
  int _otpCountdown = 0;
  Timer? _countdownTimer;
  DateTime? _countdownEnd;
  bool _disposed = false;

  UnifiedAuthStep get step => _step;
  UnifiedAuthPath? get authPath => _authPath;
  UserType? get matchedRole => _matchedRole;

  /// The 10-digit number the current OTP was sent to, once past the mobile step.
  String? get mobileDigits => _mobileDigits;

  String get otp => _otp;
  bool get sendingOtp => _sendingOtp;
  bool get verifying => _verifying;
  int get otpCountdown => _otpCountdown;
  bool get otpValid => _otp.length == AppConstants.otpLength;
  bool get busy => _sendingOtp || _verifying;

  @override
  void dispose() {
    _disposed = true;
    _countdownTimer?.cancel();
    _countdownEnd = null;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void setOtp(String value) {
    if (value == _otp) return;
    _otp = value;
    _notify();
  }

  void backToMobile() {
    _step = UnifiedAuthStep.mobile;
    _otp = '';
    _notify();
  }

  void _startOtpCountdown() {
    _countdownTimer?.cancel();
    _countdownEnd = DateTime.now().add(
      const Duration(seconds: AppConstants.otpResendCooldownSeconds),
    );
    _otpCountdown = AppConstants.otpResendCooldownSeconds;
    _notify();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed) {
        t.cancel();
        return;
      }
      final remaining =
          _countdownEnd?.difference(DateTime.now()).inSeconds ?? 0;
      if (remaining <= 0) {
        t.cancel();
        _otpCountdown = 0;
        _countdownEnd = null;
      } else {
        _otpCountdown = remaining;
      }
      _notify();
    });
  }

  /// Sends OTP and advances to [UnifiedAuthStep.otp].
  /// Does NOT leak registered status before OTP is verified.
  Future<void> sendOtp(BuildContext context, String rawMobile) async {
    if (_sendingOtp || _verifying) return;

    final digits = FormValidators.registrationMobileDigits(rawMobile);
    if (digits == null) {
      AppToast.error(context, 'Enter a valid 10-digit mobile number.');
      return;
    }

    if (!FirebaseBootstrap.isReady) {
      final ready = await FirebaseBootstrap.initialize();
      if (!ready && context.mounted) {
        AppToast.error(
          context,
          FirebaseBootstrap.lastInitError ??
              'Could not connect. Check your network and try again.',
        );
        return;
      }
    }

    _sendingOtp = true;
    _notify();
    try {
      // ONE phone step for login and registration (otpType 'auth'): no account lookup and
      // no client-side demo/role mapping before the OTP is verified. The server decides the
      // role, the data plane and whether a demo number may use the fixed OTP.
      _matchedRole = null;
      final res = await RegistrationOtpService.sendOtp(
        digits,
        role: UserType.patient,
        otpType: 'auth',
      );
      if (!context.mounted) return;
      if (res.error != null) {
        AppToast.error(context, res.error!);
        return;
      }

      _authPath = null;
      _mobileDigits = digits;
      _step = UnifiedAuthStep.otp;
      _otp = '';
      _startOtpCountdown();
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(
        context,
        describeUserFacingError(e, fallback: 'Failed to send OTP'),
      );
    } finally {
      _sendingOtp = false;
      _notify();
    }
  }

  /// Deliberately leaves [step] on the OTP screen while resending, so neither
  /// surface flashes the number form mid-request.
  Future<void> resendOtp(BuildContext context) async {
    final digits = _mobileDigits;
    if (_sendingOtp || _otpCountdown > 0 || digits == null) return;
    await sendOtp(context, digits);
  }

  /// LOGIN vs REGISTER (transparent to user), decided only after the OTP is verified:
  /// - Registered number (including the five demo numbers): signs in with the role the
  ///   server returns for that account. No role selection screen.
  /// - Unknown number: continues to registration (role selection, or the invited role).
  Future<void> verifyOtp(BuildContext context) async {
    final digits = _mobileDigits;
    if (_verifying || digits == null) return;
    if (_otp.length != AppConstants.otpLength) {
      AppToast.error(context, 'Enter the 6-digit OTP.');
      return;
    }

    _verifying = true;
    _notify();
    try {
      final verifyError = await RegistrationOtpService.verify(
        digits,
        _otp,
        role: UserType.patient,
        otpType: 'auth',
      );
      if (!context.mounted) return;
      if (verifyError != null) {
        AppToast.error(context, verifyError);
        return;
      }

      final postVerify = RegistrationOtpService.postVerifyAccountLookup;
      if (postVerify.exists == true) {
        final targetRole = loginRoleFromServer(postVerify.role);
        if (targetRole == null) {
          // Never guess (an older backend omits the role): a guessed "patient" signs
          // doctors/labs/pharmacies into the wrong module or fails with a role mismatch.
          AppToast.error(
            context,
            'Could not determine your account type. Please update the app or try again later.',
          );
          return;
        }
        _matchedRole = targetRole;
        _authPath = UnifiedAuthPath.login;
        await _completeLoginAfterVerifiedOtp(
          context,
          digits,
          targetRole: targetRole,
        );
        return;
      }

      _matchedRole = null;
      _authPath = UnifiedAuthPath.register;
      await _openRegistrationAfterVerifiedOtp(context, digits);
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(
        context,
        describeUserFacingError(e, fallback: 'Verification failed'),
      );
    } finally {
      _verifying = false;
      _notify();
    }
  }

  static Future<void> completeAmbulanceLogin(
    BuildContext context,
    String digits,
    String otp,
  ) async {
    final signedIn = await AmbulanceAuthHelper.ensureSignedIn();
    if (!signedIn) {
      if (!context.mounted) return;
      AppToast.error(
        context,
        'Could not start a secure session. Please try again.',
      );
      return;
    }

    final verifyError = await RegistrationOtpService.verify(
      digits,
      otp,
      role: UserType.ambulance,
      otpType: 'login',
    );
    if (!context.mounted) return;
    if (verifyError != null) {
      AppToast.error(context, verifyError);
      return;
    }

    final sessionId = RegistrationOtpService.verificationSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      AppToast.error(context, 'OTP session expired. Please request a new OTP.');
      return;
    }
    await finishAmbulanceLogin(context, digits, sessionId);
  }

  /// Completes an ambulance driver login with an already verified OTP session.
  static Future<void> finishAmbulanceLogin(
    BuildContext context,
    String digits,
    String sessionId,
  ) async {
    final login = await AmbulanceRepository.instance
        .verifyDriverMobileLogin(mobile: digits, sessionId: sessionId);
    RegistrationOtpService.clearVerificationSession();

    if (!context.mounted) return;
    if (!login.ok || login.profile == null) {
      AppToast.error(
        context,
        login.errorMessage ??
            'No ambulance account found for this mobile number.',
      );
      return;
    }

    final match = login.profile!;
    final username = match.username.trim().toLowerCase();
    unawaited(
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('last_login_ambulance_username', username);
      }),
    );
    await AmbulanceLoginCache.save(match);
    await AmbulanceSession.setAmbulance(
      id: match.id,
      serviceName: match.serviceName,
      driverName: match.driverName,
    );
    await AmbulanceRepository.instance.linkDriverAuth(match.id);

    final fresh = AmbulanceStore.instance.findAmbulance(match.id) ?? match;
    final realName = fresh.driverName.trim().isNotEmpty
        ? fresh.driverName.trim()
        : fresh.serviceName.trim();
    if (!NameValidator.isRealName(realName)) {
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => OnboardingNameScreen(
            role: UserType.ambulance,
            mobileDigits: digits,
          ),
        ),
        (_) => false,
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const DashboardShell(userType: UserType.ambulance),
      ),
      (_) => false,
    );
  }

  Future<void> _completeLoginAfterVerifiedOtp(
    BuildContext context,
    String digits, {
    required UserType targetRole,
  }) async {
    AppSession.clear();

    if (targetRole == UserType.ambulance) {
      if (!AmbulanceEnabled.isOn) {
        if (!context.mounted) return;
        AppToast.error(
          context,
          'Ambulance sign-in is not available in this build.',
        );
        return;
      }
      // The OTP was already consumed by the unified verify step: finish with its session.
      final sessionId = RegistrationOtpService.verificationSessionId;
      if (sessionId == null || sessionId.isEmpty) {
        if (!context.mounted) return;
        AppToast.error(
            context, 'OTP session expired. Please request a new OTP.');
        return;
      }
      final signedIn = await AmbulanceAuthHelper.ensureSignedIn();
      if (!signedIn) {
        if (!context.mounted) return;
        AppToast.error(
          context,
          'Could not start a secure session. Please try again.',
        );
        return;
      }
      if (!context.mounted) return;
      await finishAmbulanceLogin(context, digits, sessionId);
      return;
    }

    final result = await FirebaseAuthService.instance.signInWithMobileOtp(
      expectedRole: targetRole,
      mobile: digits,
      otpCode: _otp,
      skipOtpVerify: true,
    );
    if (!context.mounted) return;
    await UnifiedAuthNavigation.handleSignInResult(
      context,
      role: targetRole,
      result: result,
    );
  }

  Future<void> _openRegistrationAfterVerifiedOtp(
    BuildContext context,
    String digits,
  ) async {
    if (FirebaseAuthService.instance.isSignedIn) {
      try {
        await FirebaseAuthService.instance.signOut();
      } catch (_) {}
    }

    if (RegistrationOtpService.verificationSessionId == null) {
      AppToast.error(context, 'OTP session expired. Please request a new OTP.');
      return;
    }

    if (role != null) {
      UnifiedAuthNavigation.openRegistrationForm(
        context,
        role: role!,
        mobileDigits: digits,
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => WelcomeScreen(
            verifiedMobile: digits,
            verifiedOtp: _otp,
            isNewUser: true,
          ),
        ),
      );
    }
  }
}
