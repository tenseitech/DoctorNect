import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/auth/unified_auth_flow_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/country_phone_codes.dart';
import '../../core/enums/user_type.dart';
import '../../core/legal/legal_document_modal.dart';
import '../../core/legal/medibond_legal_content.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/validators/form_validators.dart';
import '../../widgets/otp_input.dart';
import 'auth_autoflow_helper.dart';
import 'trouble_signing_in_screen.dart';
import 'widgets/auth_layout.dart';
import 'widgets/unified_auth_mobile_field.dart';

/// Screen 2 — Enter Mobile Number & OTP Verification.
///
/// Features:
/// - AppBar with back arrow (left) and Help with "?" icon (right)
/// - Title "Enter your mobile number"
/// - Row: Country code selector (+91 default, dropdown) + mobile TextField
/// - Digits only, max 10, autofocus, inline error for invalid numbers
/// - "By continuing, you agree to our Terms & Conditions" tappable link
/// - Full-width Continue button (disabled/grey until 10 digits, brand color when valid)
/// - Transitions to existing OTP step on success, with countdown, resend & verify
/// - Responsive: centered in max-width 420px card on large web/desktop screens
/// - Light & dark mode theme tokens with zero overflow
class UnifiedMobileAuthScreen extends StatefulWidget {
  const UnifiedMobileAuthScreen({
    super.key,
    this.role,
    this.accentColor,
    this.initialMobile,
    this.mobileHeroTag,
    this.focusMobileAfterTransition = false,
  });

  final UserType? role;
  final Color? accentColor;
  final String? initialMobile;
  final String? mobileHeroTag;
  final bool focusMobileAfterTransition;

  @override
  State<UnifiedMobileAuthScreen> createState() =>
      _UnifiedMobileAuthScreenState();
}

class _UnifiedMobileAuthScreenState extends State<UnifiedMobileAuthScreen> {
  final _mobileController = TextEditingController();
  final _mobileFocusNode = FocusNode();
  final _otpInputKey = GlobalKey<OtpInputState>();
  final _mobileTracker = MobileAutoSendTracker();

  CountryPhoneCode _countryCode = CountryPhoneCodes.defaultEntry;
  late final UnifiedAuthFlowController _flow;

  bool _transitionFocusScheduled = false;
  bool _isAutoSending = false;
  bool _isVerifying = false;
  String? _lastFailedOtp;
  String? _inlineError;
  UnifiedAuthStep? _stepOverride;

  UnifiedAuthStep get _effectiveStep => _stepOverride ?? _flow.step;
  bool get _isMobileStep => _effectiveStep == UnifiedAuthStep.mobile;

  Color get _accent =>
      widget.accentColor ??
      (widget.role == UserType.doctor
          ? AppColors.doctorBlue
          : AppColors.patientTeal);

  LegalAudience get _legalAudience => switch (widget.role) {
        UserType.doctor => LegalAudience.doctor,
        UserType.patient => LegalAudience.patient,
        UserType.medicalStore => LegalAudience.pharmacy,
        UserType.lab => LegalAudience.lab,
        UserType.ambulance => LegalAudience.ambulance,
        _ => LegalAudience.patient,
      };

  bool get _mobileValid {
    final digits = FormValidators.registrationMobileDigits(
      _mobileController.text,
    );
    return digits != null && digits.length == 10;
  }

  @override
  void initState() {
    super.initState();
    _flow = UnifiedAuthFlowController(role: widget.role)
      ..addListener(_onFlowChanged);
    final initial = widget.initialMobile;
    if (initial != null && initial.isNotEmpty) {
      _mobileTracker.initialize(initial);
      _mobileController.text = initial;
    }
    _mobileController.addListener(_onMobileInputChanged);
  }

  void _onMobileInputChanged() {
    if (!mounted) return;
    _mobileTracker.checkAndNormalize(_mobileController);
    if (_inlineError != null) {
      setState(() => _inlineError = null);
    } else {
      setState(() {});
    }
  }

  void _onFlowChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleFocusAfterRouteTransition();
  }

  void _scheduleFocusAfterRouteTransition() {
    if (!widget.focusMobileAfterTransition || _transitionFocusScheduled) return;
    _transitionFocusScheduled = true;

    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _requestMobileFocusOnce(),
      );
      return;
    }

    void onAnimationStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        animation.removeStatusListener(onAnimationStatus);
        _requestMobileFocusOnce();
      }
    }

    animation.addStatusListener(onAnimationStatus);
  }

  void _requestMobileFocusOnce() {
    if (!mounted || !_isMobileStep) return;
    _mobileFocusNode.requestFocus();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _mobileController.removeListener(_onMobileInputChanged);
    _mobileController.dispose();
    _mobileFocusNode.dispose();
    _flow
      ..removeListener(_onFlowChanged)
      ..dispose();
    super.dispose();
  }

  void _openTerms() {
    _dismissKeyboard();
    showLegalDocumentModal(
      context,
      type: LegalDocumentType.termsOfService,
      audience: _legalAudience,
      accentColor: _accent,
    );
  }

  void _openTroubleSigningInHelp() {
    _dismissKeyboard();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TroubleSigningInScreen(
          accentColor: _accent,
          onReenterMobile: () {
            if (!_isMobileStep) {
              _stepOverride = null;
              _mobileTracker.onReturnedFromOtp(_mobileController.text);
              _flow.backToMobile();
            }
            _mobileFocusNode.requestFocus();
          },
        ),
      ),
    );
  }

  void _handleBack() {
    if (!_isMobileStep) {
      _stepOverride = null;
      _mobileTracker.onReturnedFromOtp(_mobileController.text);
      _flow.backToMobile();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _continueWithMobile({bool isAuto = false}) async {
    if (_isAutoSending || _flow.busy) return;
    final digits =
        FormValidators.registrationMobileDigits(_mobileController.text);
    if (digits == null || digits.length != 10) {
      if (!isAuto) {
        setState(() {
          _inlineError = 'Please enter a valid 10-digit mobile number';
        });
      }
      return;
    }

    // Cooldown check for same number
    if (digits == _flow.mobileDigits && _flow.otpCountdown > 0) {
      _stepOverride = UnifiedAuthStep.otp;
      setState(() {});
      return;
    }

    _isAutoSending = true;
    _stepOverride = null;
    setState(() => _inlineError = null);

    try {
      await _flow.sendOtp(context, digits);
    } catch (e) {
      if (mounted) {
        setState(() {
          _inlineError =
              e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        });
      }
    } finally {
      _isAutoSending = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _verifyOtp({bool isAuto = false}) async {
    if (_isVerifying || _flow.verifying) return;
    final otp = _flow.otp;
    if (otp.length != AppConstants.otpLength) {
      if (!isAuto) _flow.verifyOtp(context);
      return;
    }

    if (isAuto && otp == _lastFailedOtp) return;

    _isVerifying = true;
    setState(() {});

    bool hadNetworkException = false;

    try {
      await _flow.verifyOtp(context);
    } catch (e) {
      hadNetworkException =
          AuthAutoFlowHelper.isNetworkOrServerError(e.toString());
    } finally {
      _isVerifying = false;
      if (mounted) setState(() {});
    }

    if (!mounted) return;

    if (!_isMobileStep) {
      _lastFailedOtp = otp;
      final isNetwork =
          hadNetworkException || AuthAutoFlowHelper.isOfflineOrUnavailable();
      if (!isNetwork) {
        _otpInputKey.currentState?.shakeAndClear();
      }
    }
  }

  Future<void> _resendOtp() async {
    final digits = _flow.mobileDigits;
    if (digits == null) return;
    _mobileController.text = digits;
    await _flow.resendOtp(context);
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _handleBack,
            color: AppColors.textPrimaryOf(context),
            tooltip: 'Back',
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _openTroubleSigningInHelp,
            icon: Icon(
              Icons.help_outline_rounded,
              size: 18,
              color: AppColors.textSecondaryOf(context),
            ),
            label: Text(
              'Help',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileStep(BuildContext context) {
    Widget field = UnifiedAuthMobileField(
      controller: _mobileController,
      focusNode: _mobileFocusNode,
      countryCode: _countryCode,
      enableCountryPicker: true,
      onCountryChanged: (code) => setState(() => _countryCode = code),
      inlineError: _inlineError,
      onSubmitted: (_) => _continueWithMobile(isAuto: false),
    );

    final heroTag = widget.mobileHeroTag;
    if (heroTag != null) {
      field = Hero(
        tag: heroTag,
        child: Material(color: Colors.transparent, child: field),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter your mobile number',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryOf(context),
            letterSpacing: -0.4,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We will send a 6-digit verification code to verify your number.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: AppColors.textSecondaryOf(context),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        field,
        const SizedBox(height: 16),
        _TermsDisclaimer(
          accentColor: _accent,
          onTermsTap: _openTerms,
        ),
      ],
    );
  }

  Widget _buildOtpStep(BuildContext context) {
    final mobile = _flow.mobileDigits ?? _mobileController.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter verification code',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryOf(context),
            letterSpacing: -0.4,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Sent to ${_countryCode.dialCode} $mobile',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                _stepOverride = null;
                _flow.backToMobile();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Edit',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        OtpInput(
          key: _otpInputKey,
          accentColor: _accent,
          autofocus: true,
          enabled: !_isVerifying && !_flow.busy,
          onChanged: (val) {
            _flow.setOtp(val);
            if (_lastFailedOtp != null && val != _lastFailedOtp) {
              _lastFailedOtp = null;
            }
          },
          onCompleted: (_) => _verifyOtp(isAuto: true),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed:
                (_flow.busy || _flow.otpCountdown > 0) ? null : _resendOtp,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _flow.otpCountdown > 0
                  ? 'Resend OTP in ${_flow.otpCountdown}s'
                  : 'Resend OTP',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
                color: _flow.otpCountdown > 0
                    ? AppColors.textSecondaryOf(context)
                    : _accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobileStep = _isMobileStep;
    final canContinue = isMobileStep
        ? _mobileValid && !_flow.sendingOtp && !_isAutoSending
        : _flow.otpValid && !_flow.verifying && !_isVerifying;
    final isLoading = isMobileStep
        ? (_flow.sendingOtp || _isAutoSending)
        : (_flow.verifying || _isVerifying);

    final continueButton = _FullWidthContinueButton(
      label: isMobileStep ? 'Continue' : 'Verify & Continue',
      accentColor: _accent,
      enabled: canContinue,
      loading: isLoading,
      loadingText: isMobileStep ? 'Sending OTP...' : 'Verifying...',
      onPressed: isMobileStep
          ? () => _continueWithMobile(isAuto: false)
          : () => _verifyOtp(isAuto: false),
    );

    final mobileBody = Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: _dismissKeyboard,
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(context),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: isMobileStep
                      ? _buildMobileStep(context)
                      : _buildOtpStep(context),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                child: continueButton,
              ),
            ],
          ),
        ),
      ),
    );

    return AuthLayout(
      showBackButton: true,
      onBack: _handleBack,
      showHelpButton: true,
      onHelp: _openTroubleSigningInHelp,
      formMaxWidth: kAuthDesktopFormMaxWidth,
      mobileBody: mobileBody,
      desktopForm: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          isMobileStep ? _buildMobileStep(context) : _buildOtpStep(context),
          const SizedBox(height: 24),
          continueButton,
        ],
      ),
    );
  }
}

/// "By continuing, you agree to our Terms & Conditions" link
class _TermsDisclaimer extends StatelessWidget {
  const _TermsDisclaimer({
    required this.accentColor,
    required this.onTermsTap,
  });

  final Color accentColor;
  final VoidCallback onTermsTap;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: AppColors.textSecondaryOf(context),
          height: 1.45,
        ),
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(
            text: 'Terms & Conditions',
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: accentColor.withValues(alpha: 0.5),
            ),
            recognizer: TapGestureRecognizer()..onTap = onTermsTap,
          ),
        ],
      ),
    );
  }
}

/// Full-width Continue button (disabled/grey until valid digits).
class _FullWidthContinueButton extends StatelessWidget {
  const _FullWidthContinueButton({
    required this.label,
    required this.accentColor,
    required this.enabled,
    required this.loading,
    required this.loadingText,
    required this.onPressed,
  });

  final String label;
  final Color accentColor;
  final bool enabled;
  final bool loading;
  final String loadingText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final disabledBg =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final disabledFg =
        isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: (enabled && !loading) ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          disabledBackgroundColor: disabledBg,
          foregroundColor: Colors.white,
          disabledForegroundColor: disabledFg,
          elevation: enabled ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: loading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    loadingText,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
