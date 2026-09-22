import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sms_autofill/sms_autofill.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

/// Six-box OTP entry with auto-advance, multi-digit paste/autofill support, and backspace.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.onChanged,
    this.onCompleted,
    this.accentColor = AppColors.doctorBlue,
    this.autofocus = false,
    this.initialValue,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final Color accentColor;
  final bool autofocus;
  final String? initialValue;

  static const _boxWidth = 44.0;
  static const _boxHeight = 52.0;
  static const _boxGap = 12.0;

  /// Total width of the OTP row at its natural (unscaled) size.
  static double get intrinsicRowWidth =>
      AppConstants.otpLength * _boxWidth +
      (AppConstants.otpLength - 1) * _boxGap;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> with CodeAutoFill {
  final List<TextEditingController> _controllers =
      List.generate(AppConstants.otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(AppConstants.otpLength, (_) => FocusNode());

  bool get _supportsAndroidSmsAutofill =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  OutlineInputBorder _boxBorder(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.inputRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  void initState() {
    super.initState();
    _startSmsAutofill();
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setFullOtp(widget.initialValue!);
      });
    } else if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNodes.first.requestFocus();
      });
    }
  }

  Future<void> _startSmsAutofill() async {
    if (!_supportsAndroidSmsAutofill) return;
    try {
      await SmsAutoFill().listenForCode();
      listenForCode();
    } catch (_) {
      // Manual entry remains available when auto-read fails or is denied.
    }
  }

  @override
  void codeUpdated() {
    final received = code;
    if (received == null || received.isEmpty || !mounted) return;
    _setFullOtp(received);
  }

  @override
  void didUpdateWidget(covariant OtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
        _setFullOtp(widget.initialValue!);
      } else {
        _clearAll();
      }
    }
  }

  void _clearAll() {
    for (final c in _controllers) {
      c.clear();
    }
    if (mounted && _focusNodes.isNotEmpty) {
      _focusNodes.first.requestFocus();
    }
  }

  @override
  void dispose() {
    if (_supportsAndroidSmsAutofill) {
      try {
        cancel();
        SmsAutoFill().unregisterListener();
      } catch (_) {}
    }
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _notify() {
    final otp = _otp;
    widget.onChanged(otp);
    if (otp.length == AppConstants.otpLength) {
      widget.onCompleted?.call(otp);
    }
  }

  void _setFullOtp(String value) {
    final digits = _OtpTextFormatter.extractOtp(value);
    if (digits.isEmpty) return;

    final chars = digits.characters.take(AppConstants.otpLength).toList();
    for (int i = 0; i < AppConstants.otpLength; i++) {
      if (i < chars.length) {
        _controllers[i].text = chars[i];
      } else {
        _controllers[i].clear();
      }
    }

    if (chars.length == AppConstants.otpLength) {
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      final nextFocus = chars.length;
      if (_focusNodes.length > nextFocus) {
        _focusNodes[nextFocus].requestFocus();
      }
    }

    _notify();
    if (mounted) setState(() {});
  }

  void _onChanged(int index, String value) {
    final extracted = _OtpTextFormatter.extractOtp(value);

    // If a 6-digit OTP was pasted or autofilled into ANY box, populate all boxes
    if (extracted.length == AppConstants.otpLength) {
      _setFullOtp(extracted);
      return;
    }

    // If user typed over an existing character (length > 1 but < 6)
    if (value.length > 1) {
      final newChar = value.characters.last;
      _controllers[index].text = newChar;
      _controllers[index].selection = const TextSelection.collapsed(offset: 1);
      if (index < AppConstants.otpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      }
      _notify();
      setState(() {});
      return;
    }

    // Single character entered
    if (value.isNotEmpty && index < AppConstants.otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    _notify();
    setState(() {});
  }

  KeyEventResult _onKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_controllers[index].text.isEmpty && index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      _notify();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int index = 0; index < AppConstants.otpLength; index++) ...[
            if (index > 0) const SizedBox(width: OtpInput._boxGap),
            SizedBox(
              width: OtpInput._boxWidth,
              height: OtpInput._boxHeight,
              child: Focus(
                onKeyEvent: (node, event) => _onKeyEvent(index, event),
                child: TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  style: TextStyle(
                    fontSize: AppTypography.headlineMedium,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.cardBgOf(context),
                    contentPadding: EdgeInsets.zero,
                    border: _boxBorder(AppColors.borderOf(context)),
                    enabledBorder: _boxBorder(AppColors.borderOf(context)),
                    focusedBorder: _boxBorder(widget.accentColor, 1.5),
                  ),
                  inputFormatters: [_OtpTextFormatter()],
                  onChanged: (v) => _onChanged(index, v),
                  onTap: () => _controllers[index].selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _controllers[index].text.length,
                  ),
                  onEditingComplete: () {
                    if (index < AppConstants.otpLength - 1) {
                      _focusNodes[index + 1].requestFocus();
                    }
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Formatter that extracts a valid 6-digit OTP from text (including pasted SMS or formatted codes),
/// or limits manual entry to digits.
class _OtpTextFormatter extends TextInputFormatter {
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

    // If text was pasted/inserted into an already populated box, isolate what was inserted
    String inserted = newText;
    if (oldValue.text.isNotEmpty && newText.length > oldValue.text.length) {
      final old = oldValue.text;
      if (newText.startsWith(old)) {
        inserted = newText.substring(old.length);
      } else if (newText.endsWith(old)) {
        inserted = newText.substring(0, newText.length - old.length);
      }
    }

    // Check if inserted text or the full text contains a valid 6-digit OTP
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

    // Otherwise, strip non-digits and cap at otpLength
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
