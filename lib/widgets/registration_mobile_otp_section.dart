import 'dart:async';

import '../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/enums/user_type.dart';
import '../core/auth/registration_otp_service.dart';
import '../core/auth/mobile_registration_lookup.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/country_phone_codes.dart';
import '../core/theme/app_colors.dart';
import '../core/validators/form_validators.dart';
import 'otp_input.dart';
import 'phone_number_field.dart';

/// Unified mobile number + OTP verification block for registration flows.
class RegistrationMobileOtpSection extends StatefulWidget {
  const RegistrationMobileOtpSection({
    super.key,
    required this.mobileController,
    required this.role,
    required this.accentColor,
    required this.onVerifiedChanged,
    required this.phoneDecoration,
    this.initialDialCode = CountryPhoneCodes.defaultDialCode,
    this.onDialCodeChanged,
    this.phoneLabel = 'Mobile number *',
  });

  final TextEditingController mobileController;
  final UserType role;
  final Color accentColor;
  final ValueChanged<bool> onVerifiedChanged;
  final InputDecoration phoneDecoration;
  final String initialDialCode;
  final ValueChanged<String>? onDialCodeChanged;
  final String phoneLabel;

  @override
  State<RegistrationMobileOtpSection> createState() =>
      _RegistrationMobileOtpSectionState();
}

class _RegistrationMobileOtpSectionState extends State<RegistrationMobileOtpSection> {
  bool _otpSent = false;
  bool _verified = false;
  bool _sending = false;
  String _otp = '';
  String? _lastMobile;
  late String _dialCode;
  int _otpKeyCounter = 0;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  bool get _phoneLocked => _otpSent && !_verified;

  @override
  void initState() {
    super.initState();
    _dialCode = widget.initialDialCode;
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RegistrationMobileOtpSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDialCode != widget.initialDialCode) {
      _dialCode = widget.initialDialCode;
    }
  }

  String? get _mobileDigits =>
      FormValidators.registrationMobileDigits(widget.mobileController.text);

  String _maskedDigits(String digits) {
    if (digits.length <= 4) return digits;
    return '******${digits.substring(digits.length - 4)}';
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = AppConstants.otpResendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendCooldown <= 1) {
          _resendCooldown = 0;
          t.cancel();
        } else {
          _resendCooldown--;
        }
      });
    });
  }

  void _unlockPhone() {
    final mobile = widget.mobileController.text.trim();
    _cooldownTimer?.cancel();
    setState(() {
      _otpSent = false;
      _otp = '';
      _verified = false;
      _lastMobile = null;
      _resendCooldown = 0;
    });
    RegistrationOtpService.clearPending(mobile, role: widget.role);
    widget.onVerifiedChanged(false);
  }

  void _onDialCodeChanged(String code) {
    setState(() => _dialCode = code);
    widget.onDialCodeChanged?.call(code);
  }

  Future<void> _sendOtp() async {
    final digits = _mobileDigits;
    if (digits == null) {
      AppToast.info(context, 'Enter a valid 10-digit mobile number first');
      return;
    }
    if (_resendCooldown > 0) return;

    final conflict = await MobileRegistrationLookup.check(
      digits,
      role: widget.role,
      intent: MobileLookupIntent.registration,
    );
    if (!mounted) return;
    if (conflict == true) {
      AppToast.error(context, MobileRegistrationLookup.registrationConflictMessage);
      return;
    }

    setState(() => _sending = true);
    final result = await RegistrationOtpService.sendOtp(digits, role: widget.role);
    if (!mounted) return;

    if (result.error != null) {
      setState(() => _sending = false);
      AppToast.error(context, result.error!);
      return;
    }

    setState(() {
      _sending = false;
      _otpSent = true;
      _lastMobile = digits;
      _otp = '';
      _otpKeyCounter++;
    });
    _startResendCooldown();
    final sentMessage = 'OTP sent to $_dialCode ${_maskedDigits(digits)}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sentMessage),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _verifyOtp() async {
    final digits = _mobileDigits;
    if (digits == null) {
      AppToast.info(context, 'Enter a valid 10-digit mobile number');
      return;
    }
    setState(() => _sending = true);
    final error = await RegistrationOtpService.verify(digits, _otp, role: widget.role);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      AppToast.info(context, error);
      return;
    }
    setState(() => _verified = true);
    widget.onVerifiedChanged(true);
    AppToast.info(context, 'Mobile number verified');
  }

  Widget _loadingIndicator({Color? color}) {
    final spinnerColor = color ?? widget.accentColor;
    return SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: spinnerColor,
      ),
    );
  }

  ButtonStyle get _primaryButtonStyle => FilledButton.styleFrom(
        backgroundColor: widget.accentColor,
        foregroundColor: widget.accentColor.computeLuminance() > 0.5
            ? Colors.black
            : Colors.white,
        minimumSize: const Size.fromHeight(48),
      );

  Widget _buildFingerprint() {
    return Text(
      'Build ${AppConstants.registrationBuildFingerprint}',
      style: GoogleFonts.inter(
        fontSize: 10,
        color: AppColors.textSecondaryOf(context).withValues(alpha: 0.75),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_verified) {
      final digits = _lastMobile ?? _mobileDigits ?? widget.mobileController.text.trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.pharmacyGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.pharmacyGreen.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_outlined, color: AppColors.pharmacyGreen, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mobile verified ($_dialCode ${_maskedDigits(digits)})',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.pharmacyGreen,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildFingerprint(),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _sending ? null : _unlockPhone,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.pharmacyGreen,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final sentDigits = _lastMobile ?? _mobileDigits ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhoneNumberField(
          controller: widget.mobileController,
          initialDialCode: _dialCode,
          onDialCodeChanged: _onDialCodeChanged,
          labelText: widget.phoneLabel,
          counterText: '',
          enabled: !_phoneLocked,
          readOnly: _phoneLocked,
          decoration: widget.phoneDecoration,
          validator: (v) => FormValidators.phoneLocal(v, dialCode: _dialCode),
        ),
        if (_phoneLocked) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _sending ? null : _unlockPhone,
              style: TextButton.styleFrom(
                foregroundColor: widget.accentColor,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Change number'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (!_otpSent) ...[
          FilledButton(
            onPressed: _sending ? null : _sendOtp,
            style: _primaryButtonStyle,
            child: _sending ? _loadingIndicator(color: Colors.white) : const Text('Send OTP'),
          ),
        ] else ...[
          Text(
            'Enter the 6-digit code sent to $_dialCode ${_maskedDigits(sentDigits)}',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 14),
          OtpInput(
            key: ValueKey('otp-$_lastMobile-$_otpKeyCounter'),
            initialValue: _otp,
            accentColor: widget.accentColor,
            autofocus: true,
            onChanged: (v) => setState(() => _otp = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: (_otp.length == 6 && !_sending) ? _verifyOtp : null,
            style: _primaryButtonStyle,
            child: _sending
                ? _loadingIndicator(color: AppColors.surfaceOf(context))
                : const Text('Verify OTP'),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: (_sending || _resendCooldown > 0) ? null : _sendOtp,
              style: TextButton.styleFrom(
                foregroundColor: _resendCooldown > 0
                    ? AppColors.textSecondaryOf(context)
                    : widget.accentColor,
              ),
              child: Text(
                _resendCooldown > 0
                    ? 'Resend OTP in ${_resendCooldown}s'
                    : 'Resend OTP',
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _buildFingerprint(),
      ],
    );
  }
}
