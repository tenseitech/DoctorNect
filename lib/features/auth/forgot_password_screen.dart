import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/registration_otp_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/country_phone_codes.dart';
import '../../core/enums/user_type.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validators/form_validators.dart';
import '../../widgets/form_scroll_helper.dart';
import '../../widgets/phone_number_field.dart';
import 'widgets/auth_login_form_field.dart';
import 'widgets/auth_login_page_shell.dart';

enum _ResetStep { enterIdentity, enterOtp, setNewPassword }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.accentColor,
    required this.userType,
  });

  final Color accentColor;
  final UserType userType;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _phoneDialCode = CountryPhoneCodes.defaultDialCode;
  _ResetStep _step = _ResetStep.enterIdentity;
  bool _loading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  String? _otpSessionId;
  String? _verifiedMobileDigits;

  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _resendCooldown = AppConstants.otpResendCooldownSeconds;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendCooldown > 0) {
          _resendCooldown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _handlePrimaryAction() async {
    if (!_formKey.currentState!.validate()) {
      FormScrollHelper.scrollToFirstError(context);
      return;
    }

    switch (_step) {
      case _ResetStep.enterIdentity:
        await _sendPhoneOtp();
        break;
      case _ResetStep.enterOtp:
        await _verifyOtp();
        break;
      case _ResetStep.setNewPassword:
        await _submitNewPassword();
        break;
    }
  }

  Future<void> _sendPhoneOtp({bool isResend = false}) async {
    final digits = FormValidators.registrationMobileDigits(_phoneController.text.trim()) ?? '';

    if (digits.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    if (isResend) {
      RegistrationOtpService.clearPending(digits, role: widget.userType);
    }

    final result = await RegistrationOtpService.sendOtp(
      digits,
      role: widget.userType,
      otpType: 'forgot_password',
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error!),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _verifiedMobileDigits = digits;
    _startCooldown();
    setState(() {
      _step = _ResetStep.enterOtp;
      _otpController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '6-digit OTP code sent to ${_maskPhone(digits)} via SMS',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    final digits = _verifiedMobileDigits ??
        FormValidators.registrationMobileDigits(_phoneController.text.trim());

    if (digits == null || digits.isEmpty || otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the complete 6-digit OTP.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    final error = await RegistrationOtpService.verify(
      digits,
      otp,
      role: widget.userType,
      otpType: 'forgot_password',
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _otpSessionId = RegistrationOtpService.verificationSessionId ?? 'verified';
    setState(() {
      _step = _ResetStep.setNewPassword;
    });
  }

  Future<void> _submitNewPassword() async {
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    final passErr = FormValidators.password(newPass);
    if (passErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(passErr),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (newPass != confirmPass) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final digits = _verifiedMobileDigits ??
        FormValidators.registrationMobileDigits(_phoneController.text.trim());
    if (digits == null || digits.isEmpty) return;

    setState(() => _loading = true);
    final result = await RegistrationOtpService.resetPasswordWithOtp(
      role: widget.userType,
      identifier: digits,
      sessionId: _otpSessionId ?? '',
      newPassword: newPass,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Password reset failed.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Password Reset!',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          'Your password has been successfully updated. You can now sign in with your new password.',
          style: GoogleFonts.inter(fontSize: 13.5, height: 1.45, color: AppColors.textPrimaryOf(context)),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: widget.accentColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }

  String _maskPhone(String phone) {
    if (phone.length <= 4) return phone;
    return '${phone.substring(0, 2)}******${phone.substring(phone.length - 2)}';
  }

  String get _buttonLabel {
    switch (_step) {
      case _ResetStep.enterIdentity:
        return 'Send OTP';
      case _ResetStep.enterOtp:
        return 'Verify OTP';
      case _ResetStep.setNewPassword:
        return 'Update Password';
    }
  }

  String get _titleText {
    switch (_step) {
      case _ResetStep.enterIdentity:
        return 'Forgot password?';
      case _ResetStep.enterOtp:
        return 'Enter OTP code';
      case _ResetStep.setNewPassword:
        return 'Set new password';
    }
  }

  String get _subtitleText {
    switch (_step) {
      case _ResetStep.enterIdentity:
        return 'Enter your registered mobile number to securely reset your password via SMS OTP.';
      case _ResetStep.enterOtp:
        return 'Enter the 6-digit OTP code sent to your registered mobile number.';
      case _ResetStep.setNewPassword:
        return 'Enter and confirm your new secure password.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLoginPageShell(
      appBarTitle: 'Reset Password',
      accentColor: widget.accentColor,
      icon: Icons.lock_open_outlined,
      welcomeTitle: _titleText,
      subtitle: _subtitleText,
      body: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step == _ResetStep.enterIdentity) ...[
                PhoneNumberField(
                  controller: _phoneController,
                  initialDialCode: _phoneDialCode,
                  onDialCodeChanged: (code) => _phoneDialCode = code,
                  decoration: authLoginInputDecoration(
                    context: context,
                    accentColor: widget.accentColor,
                    labelText: 'Registered mobile number',
                    isRequired: true,
                    hintText: 'Enter your 10-digit mobile number',
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                  ),
                  validator: (v) => FormValidators.phoneLocal(v, dialCode: _phoneDialCode),
                ),
              ] else if (_step == _ResetStep.enterOtp) ...[
                AuthLoginFormField(
                  controller: _otpController,
                  label: '6-Digit OTP Code',
                  accentColor: widget.accentColor,
                  isRequired: true,
                  hint: '123456',
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  validator: FormValidators.otp,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handlePrimaryAction(),
                  prefixIcon: Icon(
                    Icons.lock_clock_outlined,
                    size: 20,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() => _step = _ResetStep.enterIdentity),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Change Number'),
                    ),
                    TextButton(
                      onPressed: _resendCooldown > 0 ? null : () => _sendPhoneOtp(isResend: true),
                      child: Text(
                        _resendCooldown > 0 ? 'Resend in ${_resendCooldown}s' : 'Resend OTP',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: _resendCooldown > 0 ? AppColors.textSecondaryOf(context) : widget.accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (_step == _ResetStep.setNewPassword) ...[
                AuthLoginFormField(
                  controller: _newPasswordController,
                  label: 'New Password',
                  accentColor: widget.accentColor,
                  isRequired: true,
                  obscureText: _obscureNew,
                  hint: 'At least 8 characters',
                  autofillHints: const [AutofillHints.newPassword],
                  validator: FormValidators.password,
                  textInputAction: TextInputAction.next,
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: AppColors.textSecondaryOf(context),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                const SizedBox(height: 16),
                AuthLoginFormField(
                  controller: _confirmPasswordController,
                  label: 'Confirm New Password',
                  accentColor: widget.accentColor,
                  isRequired: true,
                  obscureText: _obscureConfirm,
                  hint: 'Re-enter your new password',
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) => FormValidators.confirmPassword(v, _newPasswordController.text),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handlePrimaryAction(),
                  prefixIcon: Icon(
                    Icons.lock_reset_outlined,
                    size: 20,
                    color: AppColors.textSecondaryOf(context),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              AuthLoginPrimaryButton(
                accentColor: widget.accentColor,
                label: _buttonLabel,
                loading: _loading,
                onPressed: _handlePrimaryAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
