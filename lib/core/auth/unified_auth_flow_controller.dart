import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/ambulance/ambulance_shell.dart';
import '../../features/ambulance/data/ambulance_login_cache.dart';
import '../../features/ambulance/data/ambulance_store.dart';
import '../constants/app_constants.dart';
import '../enums/user_type.dart';
import '../firebase/ambulance_auth_helper.dart';
import '../firebase/firebase_auth_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../firebase/firebase_error_messages.dart';
import '../firebase/firestore_service.dart';
import '../notifications/app_toast.dart';
import '../session/ambulance_session.dart';
import '../validators/form_validators.dart';
import 'registration_otp_service.dart';
import 'unified_auth_coordinator.dart';
import 'unified_auth_navigation.dart';

enum UnifiedAuthStep { mobile, otp }

/// Mobile → OTP → login/register flow, owned by whichever surface renders it.
///
/// Both the full-screen mobile auth screen and the inline desktop auth card
/// drive this, so the Firebase/OTP calls and the login-vs-register branch exist
/// in exactly one place. Callers own the text field, the OTP widget and the
/// layout; this only owns the flow state and the network calls.
class UnifiedAuthFlowController extends ChangeNotifier {
  UnifiedAuthFlowController({required this.role});

  final UserType role;

  UnifiedAuthStep _step = UnifiedAuthStep.mobile;
  UnifiedAuthPath? _authPath;
  String? _mobileDigits;
  String _otp = '';
  bool _sendingOtp = false;
  bool _verifying = false;
  int _otpCountdown = 0;
  Timer? _countdownTimer;
  DateTime? _countdownEnd;
  bool _disposed = false;

  UnifiedAuthStep get step => _step;

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

  /// Resolves login vs register server-side, then sends the OTP and advances to
  /// [UnifiedAuthStep.otp]. Callers run their own form validation first.
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
      final path = await UnifiedAuthCoordinator.resolvePath(
        mobile: digits,
        role: role,
      );
      if (!context.mounted) return;

      if (path == UnifiedAuthPath.blockedWrongRole) {
        AppToast.error(context, UnifiedAuthCoordinator.wrongRoleMessage);
        return;
      }

      final otpType = UnifiedAuthCoordinator.otpTypeForPath(path);
      final res = await RegistrationOtpService.sendOtp(
        digits,
        role: role,
        otpType: otpType,
      );
      if (!context.mounted) return;
      if (res.error != null) {
        AppToast.error(context, res.error!);
        return;
      }

      _authPath = path;
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

  /// LOGIN vs REGISTER (transparent to user):
  /// - the path was resolved server-side before OTP send via
  ///   [UnifiedAuthCoordinator.resolvePath].
  /// - login: sign in with verified OTP (Firebase or ambulance mobile login).
  /// - register: OTP session is valid; open role profile form.
  Future<void> verifyOtp(BuildContext context) async {
    final digits = _mobileDigits;
    final path = _authPath;
    if (_verifying || digits == null || path == null) return;
    if (_otp.length != AppConstants.otpLength) {
      AppToast.error(context, 'Enter the 6-digit OTP.');
      return;
    }

    _verifying = true;
    _notify();
    try {
      if (path == UnifiedAuthPath.login) {
        await _completeLogin(context, digits, _otp);
      } else {
        await _completeRegistration(context, digits, _otp);
      }
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

  Future<void> _completeLogin(
    BuildContext context,
    String digits,
    String otp,
  ) async {
    if (role == UserType.ambulance) {
      await _completeAmbulanceLogin(context, digits, otp);
      return;
    }

    final result = await FirebaseAuthService.instance.signInWithMobileOtp(
      expectedRole: role,
      mobile: digits,
      otpCode: otp,
    );
    if (!context.mounted) return;
    await UnifiedAuthNavigation.handleSignInResult(
      context,
      role: role,
      result: result,
    );
  }

  Future<void> _completeAmbulanceLogin(
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

    final login =
        await FirestoreService.instance.ambulance.verifyDriverMobileLogin(
      mobile: digits,
      sessionId: sessionId,
    );
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
    await FirestoreService.instance.ambulance.linkDriverAuth(match.id);

    final fresh = AmbulanceStore.instance.findAmbulance(match.id) ?? match;
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => AmbulanceShell(ambulance: fresh)),
      (_) => false,
    );
  }

  Future<void> _completeRegistration(
    BuildContext context,
    String digits,
    String otp,
  ) async {
    final verifyError = await RegistrationOtpService.verify(
      digits,
      otp,
      role: role,
      otpType: 'registration',
    );
    if (!context.mounted) return;
    if (verifyError != null) {
      AppToast.error(context, verifyError);
      return;
    }

    if (RegistrationOtpService.verificationSessionId == null) {
      AppToast.error(context, 'OTP session expired. Please request a new OTP.');
      return;
    }

    // LOGIN vs REGISTER: registration path — OTP session is valid; collect
    // profile next.
    UnifiedAuthNavigation.openRegistrationForm(
      context,
      role: role,
      mobileDigits: digits,
    );
  }
}
