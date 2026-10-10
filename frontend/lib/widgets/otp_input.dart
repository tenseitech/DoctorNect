import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';
import 'package:smart_auth/smart_auth.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

/// Single-input OTP widget powered by [Pinput] with 6 rounded visual boxes,
/// paste support, backspace support, autofill hints, and Android SMS auto-read
/// via the SMS User Consent API.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.onChanged,
    this.onCompleted,
    this.accentColor = AppColors.doctorBlue,
    this.autofocus = false,
    this.initialValue,
    this.enabled = true,
    this.controller,
    this.focusNode,
    this.hasError = false,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final Color accentColor;
  final bool autofocus;
  final String? initialValue;
  final bool enabled;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool hasError;

  static const boxWidth = 44.0;
  static const boxHeight = 52.0;
  static const boxGap = 12.0;

  /// Total width of the OTP row at its natural (unscaled) size.
  static double get intrinsicRowWidth =>
      AppConstants.otpLength * boxWidth + (AppConstants.otpLength - 1) * boxGap;

  @override
  State<OtpInput> createState() => OtpInputState();
}

class OtpInputState extends State<OtpInput>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _internalController;
  late final FocusNode _internalFocusNode;
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  SmsRetriever? _smsRetriever;
  bool _localError = false;

  TextEditingController get _effectiveController =>
      widget.controller ?? _internalController;
  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  bool get _supportsAndroidSmsAutofill =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _internalController =
        TextEditingController(text: widget.initialValue ?? '');
    _internalFocusNode = FocusNode();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -4.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );

    if (_supportsAndroidSmsAutofill) {
      _smsRetriever = UserConsentSmsRetriever(SmartAuth.instance);
    }

    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _effectiveController.text = widget.initialValue!;
          _effectiveController.selection = TextSelection.collapsed(
            offset: widget.initialValue!.length,
          );
        }
      });
    } else if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _effectiveFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant OtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      if (widget.initialValue != null &&
          widget.initialValue != _effectiveController.text) {
        _effectiveController.text = widget.initialValue!;
        _effectiveController.selection = TextSelection.collapsed(
          offset: widget.initialValue!.length,
        );
      } else if (widget.initialValue == null || widget.initialValue!.isEmpty) {
        _effectiveController.clear();
      }
    }
    if (widget.hasError != oldWidget.hasError && !widget.hasError) {
      _localError = false;
    }
  }

  void shakeAndClear() {
    _shakeController.forward(from: 0.0);
    clearAndFocusFirst();
  }

  void clearAndFocusFirst() {
    _effectiveController.clear();
    _localError = false;
    widget.onChanged('');
    if (mounted) {
      _effectiveFocusNode.requestFocus();
      setState(() {});
    }
  }

  void clearAndFocus() => clearAndFocusFirst();

  void clear() {
    _effectiveController.clear();
    _localError = false;
    widget.onChanged('');
    if (mounted) setState(() {});
  }

  void requestFocus() {
    if (mounted) _effectiveFocusNode.requestFocus();
  }

  void clearError() {
    if (_localError && mounted) {
      setState(() => _localError = false);
    }
  }

  void setError([bool error = true]) {
    if (mounted) {
      setState(() => _localError = error);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _smsRetriever?.dispose();
    if (widget.controller == null) {
      _internalController.dispose();
    }
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: AutofillGroup(
        child: AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeAnimation.value, 0),
            child: child,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : OtpInput.intrinsicRowWidth;
              final availableForBoxesAndGaps = maxW;
              final bool needsScaling =
                  availableForBoxesAndGaps < OtpInput.intrinsicRowWidth;

              final double gap = needsScaling
                  ? ((availableForBoxesAndGaps -
                              (AppConstants.otpLength * 38.0)) /
                          (AppConstants.otpLength - 1))
                      .clamp(4.0, OtpInput.boxGap)
                  : OtpInput.boxGap;

              final double totalGaps = (AppConstants.otpLength - 1) * gap;
              final double boxW = needsScaling
                  ? ((availableForBoxesAndGaps - totalGaps) /
                          AppConstants.otpLength)
                      .clamp(34.0, OtpInput.boxWidth)
                  : OtpInput.boxWidth;

              final defaultPinTheme = PinTheme(
                width: boxW,
                height: OtpInput.boxHeight,
                textStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: boxW < 40
                      ? AppTypography.titleLarge
                      : AppTypography.headlineMedium,
                  fontWeight: FontWeight.w600,
                  color: widget.enabled
                      ? AppColors.textPrimaryOf(context)
                      : AppColors.textSecondaryOf(context),
                ),
                decoration: BoxDecoration(
                  color: widget.enabled
                      ? AppColors.cardBgOf(context)
                      : AppColors.cardBgOf(context).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppConstants.inputRadius),
                  border: Border.all(
                    color: widget.enabled
                        ? AppColors.borderOf(context)
                        : AppColors.borderOf(context).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              );

              final focusedPinTheme = defaultPinTheme.copyWith(
                decoration: defaultPinTheme.decoration!.copyWith(
                  border: Border.all(
                    color: widget.accentColor,
                    width: 1.5,
                  ),
                ),
              );

              final submittedPinTheme = defaultPinTheme;

              final disabledPinTheme = defaultPinTheme.copyWith(
                textStyle: defaultPinTheme.textStyle?.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
                decoration: defaultPinTheme.decoration!.copyWith(
                  color: AppColors.cardBgOf(context).withValues(alpha: 0.6),
                  border: Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              );

              final errorPinTheme = defaultPinTheme.copyWith(
                decoration: defaultPinTheme.decoration!.copyWith(
                  border: Border.all(
                    color: AppColors.error,
                    width: 1.5,
                  ),
                ),
              );

              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Pinput(
                  length: AppConstants.otpLength,
                  controller: _effectiveController,
                  focusNode: _effectiveFocusNode,
                  autofocus: widget.autofocus,
                  enabled: widget.enabled,
                  readOnly: !widget.enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    OtpDigitsInputFormatter(),
                  ],
                  autofillHints: const [AutofillHints.oneTimeCode],
                  smsRetriever: _smsRetriever,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: focusedPinTheme,
                  submittedPinTheme: submittedPinTheme,
                  disabledPinTheme: disabledPinTheme,
                  errorPinTheme: errorPinTheme,
                  forceErrorState: widget.hasError || _localError,
                  separatorBuilder: (index) => SizedBox(width: gap),
                  mainAxisAlignment: MainAxisAlignment.center,
                  closeKeyboardWhenCompleted: true,
                  hapticFeedbackType: HapticFeedbackType.lightImpact,
                  onChanged: (value) {
                    widget.onChanged(value);
                    if (value.length < AppConstants.otpLength && _localError) {
                      setState(() => _localError = false);
                    }
                  },
                  onCompleted: (value) {
                    widget.onCompleted?.call(value);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Implementation of [SmsRetriever] using Android's SMS User Consent API via [SmartAuth].
/// Does not require an SMS app hash.
class UserConsentSmsRetriever implements SmsRetriever {
  const UserConsentSmsRetriever(this.smartAuth);

  final SmartAuth smartAuth;

  @override
  Future<void> dispose() async {
    try {
      await smartAuth.removeUserConsentApiListener();
    } catch (_) {}
  }

  @override
  Future<String?> getSmsCode() async {
    try {
      final res = await smartAuth.getSmsWithUserConsentApi(matcher: r'\d{6}');
      if (res.hasData && res.data?.code != null) {
        return res.data!.code;
      }
    } catch (_) {}
    return null;
  }

  @override
  bool get listenForMultipleSms => false;
}

/// Formatter that extracts a valid 6-digit OTP from text (including pasted SMS or formatted codes),
/// or limits manual entry to digits.
class OtpDigitsInputFormatter extends TextInputFormatter {
  static String extractOtp(String value) {
    if (value.isEmpty) return '';
    // 1. Standalone 6-digit number (e.g. "123456", "Your DoctorNect OTP is 123456")
    final match = RegExp(r'\b\d{6}\b').firstMatch(value);
    if (match != null) return match.group(0)!;

    // 2. 3-3 format (e.g. "123-456" or "123 456")
    final splitMatch = RegExp(r'\b(\d{3})[- ](\d{3})\b').firstMatch(value);
    if (splitMatch != null) {
      return '${splitMatch.group(1)}${splitMatch.group(2)}';
    }

    // 3. Fallback: strip non-digits; if >= 6 digits, take first 6
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= AppConstants.otpLength) {
      return digits.substring(0, AppConstants.otpLength);
    }
    return digits;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    if (newText.isEmpty) return newValue;

    // If text was pasted/inserted into an existing value
    String inserted = newText;
    if (oldValue.text.isNotEmpty && newText.length > oldValue.text.length) {
      final old = oldValue.text;
      if (newText.startsWith(old)) {
        inserted = newText.substring(old.length);
      } else if (newText.endsWith(old)) {
        inserted = newText.substring(0, newText.length - old.length);
      }
    }

    // Check if inserted text or full text contains a 6-digit OTP
    final insertedOtp = extractOtp(inserted);
    if (insertedOtp.length == AppConstants.otpLength) {
      return TextEditingValue(
        text: insertedOtp,
        selection: TextSelection.collapsed(offset: insertedOtp.length),
      );
    }

    final fullOtp = extractOtp(newText);
    if (fullOtp.length == AppConstants.otpLength) {
      return TextEditingValue(
        text: fullOtp,
        selection: TextSelection.collapsed(offset: fullOtp.length),
      );
    }

    // Otherwise strip non-digits and cap at AppConstants.otpLength
    final digits = newText.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > AppConstants.otpLength
        ? digits.substring(0, AppConstants.otpLength)
        : digits;

    return TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
  }
}
