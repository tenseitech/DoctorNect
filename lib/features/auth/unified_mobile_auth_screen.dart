import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/unified_auth_flow_controller.dart';
import '../../core/enums/user_type.dart';
import '../../core/legal/legal_document_modal.dart';
import '../../core/legal/medibond_legal_content.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/validators/form_validators.dart';
import '../../widgets/otp_input.dart';
import 'widgets/unified_auth_mobile_field.dart';
import 'trouble_signing_in_screen.dart';

/// Single entry point for login and registration: mobile + OTP, then server-side branch.
class UnifiedMobileAuthScreen extends StatefulWidget {
  const UnifiedMobileAuthScreen({
    super.key,
    required this.role,
    this.accentColor,
    this.initialMobile,
    this.mobileHeroTag,
    this.focusMobileAfterTransition = false,
  });

  final UserType role;
  final Color? accentColor;
  final String? initialMobile;
  final String? mobileHeroTag;

  /// When true, focus is requested once after the push route animation completes
  /// (used by the intro → full-screen Hero transition to avoid keyboard flicker).
  final bool focusMobileAfterTransition;

  @override
  State<UnifiedMobileAuthScreen> createState() =>
      _UnifiedMobileAuthScreenState();
}

class _UnifiedMobileAuthScreenState extends State<UnifiedMobileAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _mobileFocusNode = FocusNode();

  late final UnifiedAuthFlowController _flow;
  bool _transitionFocusScheduled = false;

  Color get _accent => widget.accentColor ?? _defaultAccent;

  Color get _defaultAccent => switch (widget.role) {
        UserType.doctor => AppColors.doctorBlue,
        UserType.patient => AppColors.patientTeal,
        UserType.medicalStore => AppColors.pharmacyGreen,
        UserType.lab => AppColors.labPurple,
        UserType.ambulance => const Color(0xFFDC2626),
        _ => AppColors.doctorBlue,
      };

  LegalAudience get _legalAudience => switch (widget.role) {
        UserType.doctor => LegalAudience.doctor,
        UserType.patient => LegalAudience.patient,
        UserType.medicalStore => LegalAudience.pharmacy,
        UserType.lab => LegalAudience.lab,
        UserType.ambulance => LegalAudience.ambulance,
        _ => LegalAudience.patient,
      };

  bool get _mobileValid {
    final digits =
        FormValidators.registrationMobileDigits(_mobileController.text);
    return digits != null && digits.length == 10;
  }

  @override
  void initState() {
    super.initState();
    _flow = UnifiedAuthFlowController(role: widget.role)
      ..addListener(_onFlowChanged);
    final initial = widget.initialMobile;
    if (initial != null && initial.isNotEmpty) {
      _mobileController.text = initial;
    }
    _mobileController.addListener(() {
      if (mounted) setState(() {});
    });
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
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _requestMobileFocusOnce());
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
    if (!mounted || _flow.step != UnifiedAuthStep.mobile) return;
    _mobileFocusNode.requestFocus();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
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
            if (_flow.step == UnifiedAuthStep.otp) _flow.backToMobile();
            _mobileFocusNode.requestFocus();
          },
        ),
      ),
    );
  }

  void _handleBack() {
    if (_flow.step == UnifiedAuthStep.otp) {
      _flow.backToMobile();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _continueWithMobile() async {
    if (_flow.busy) return;
    if (!_formKey.currentState!.validate()) return;
    await _flow.sendOtp(context, _mobileController.text);
  }

  Future<void> _resendOtp() async {
    final digits = _flow.mobileDigits;
    if (digits == null) return;
    _mobileController.text = digits;
    await _flow.resendOtp(context);
  }

  String get _heading => _flow.step == UnifiedAuthStep.mobile
      ? 'Enter your mobile number'
      : 'Enter the OTP sent to +91 ${_flow.mobileDigits ?? ''}';

  Widget _buildMobileStep() {
    Widget field = UnifiedAuthMobileField(
      controller: _mobileController,
      focusNode: _mobileFocusNode,
      validator: FormValidators.mobile,
      onSubmitted: (_) => _continueWithMobile(),
    );
    final heroTag = widget.mobileHeroTag;
    if (heroTag != null) {
      field = Hero(
        tag: heroTag,
        child: Material(
          color: Colors.transparent,
          child: field,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        const SizedBox(height: 20),
        _TermsDisclaimer(
          accentColor: _accent,
          onTermsTap: _openTerms,
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OtpInput(
          accentColor: _accent,
          autofocus: true,
          onChanged: _flow.setOtp,
          onCompleted: (_) => _flow.verifyOtp(context),
        ),
        const SizedBox(height: 16),
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
              style: GoogleFonts.inter(
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
    final isMobileStep = _flow.step == UnifiedAuthStep.mobile;
    final canContinue = isMobileStep
        ? _mobileValid && !_flow.sendingOtp
        : _flow.otpValid && !_flow.verifying;
    final isLoading = isMobileStep ? _flow.sendingOtp : _flow.verifying;

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: _accent),
      ),
      child: Scaffold(
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
                _AuthTopBar(
                  onBack: _handleBack,
                  onHelp: _openTroubleSigningInHelp,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _heading,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.headlineLarge,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryOf(context),
                              letterSpacing: -0.4,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (isMobileStep)
                            _buildMobileStep()
                          else
                            _buildOtpStep(),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: _PinnedPrimaryButton(
                    label: isMobileStep ? 'Continue' : 'Verify & continue',
                    accentColor: _accent,
                    enabled: canContinue,
                    loading: isLoading,
                    loadingText:
                        isMobileStep ? 'Sending OTP...' : 'Verifying...',
                    onPressed: isMobileStep
                        ? () {
                            _dismissKeyboard();
                            _continueWithMobile();
                          }
                        : () {
                            _dismissKeyboard();
                            _flow.verifyOtp(context);
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthTopBar extends StatelessWidget {
  const _AuthTopBar({
    required this.onBack,
    required this.onHelp,
  });

  final VoidCallback onBack;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
            color: AppColors.textPrimaryOf(context),
            tooltip: 'Back',
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onHelp,
            icon: Icon(
              Icons.help_outline_rounded,
              size: 18,
              color: AppColors.textSecondaryOf(context),
            ),
            label: Text(
              'Help',
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class _TermsDisclaimer extends StatelessWidget {
  const _TermsDisclaimer({
    required this.accentColor,
    required this.onTermsTap,
  });

  final Color accentColor;
  final VoidCallback onTermsTap;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = GoogleFonts.inter(
      fontSize: AppTypography.bodySmall,
      height: 1.5,
      color: AppColors.textSecondaryOf(context),
    );
    final linkStyle = bodyStyle.copyWith(
      color: accentColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: accentColor,
    );

    return Text.rich(
      TextSpan(
        style: bodyStyle,
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(
            text: 'Terms & Conditions',
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = onTermsTap,
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

class _PinnedPrimaryButton extends StatelessWidget {
  const _PinnedPrimaryButton({
    required this.label,
    required this.accentColor,
    required this.enabled,
    required this.loading,
    required this.onPressed,
    this.loadingText,
  });

  final String label;
  final Color accentColor;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;
  final String? loadingText;

  @override
  Widget build(BuildContext context) {
    final disabledFill = AppColors.borderOf(context);
    final disabledText = AppColors.textSecondaryOf(context);

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: (enabled && !loading) ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          disabledBackgroundColor: disabledFill,
          foregroundColor: Colors.white,
          disabledForegroundColor: disabledText,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: loading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: enabled ? Colors.white : disabledText,
                    ),
                  ),
                  if (loadingText != null && loadingText!.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Text(
                      loadingText!,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelLarge,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.labelLarge,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
      ),
    );
  }
}
