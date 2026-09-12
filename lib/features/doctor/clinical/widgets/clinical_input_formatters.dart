import 'package:flutter/services.dart';

/// Digits-only input with a maximum length.
class DigitsMaxInputFormatter extends TextInputFormatter {
  const DigitsMaxInputFormatter(this.maxDigits);

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmed = digits.length > maxDigits ? digits.substring(0, maxDigits) : digits;
    return TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
  }
}

/// Numeric input with optional decimal point (no letters).
class DecimalInputFormatter extends TextInputFormatter {
  const DecimalInputFormatter({
    this.maxIntegerDigits = 3,
    this.maxDecimalDigits = 1,
  });

  final int maxIntegerDigits;
  final int maxDecimalDigits;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final dotIndex = text.indexOf('.');
    if (dotIndex >= 0) {
      final before = text.substring(0, dotIndex).replaceAll('.', '');
      var after = text.substring(dotIndex + 1).replaceAll('.', '');
      if (after.length > maxDecimalDigits) {
        after = after.substring(0, maxDecimalDigits);
      }
      final intPart = before.length > maxIntegerDigits
          ? before.substring(0, maxIntegerDigits)
          : before;
      text = after.isEmpty && newValue.text.endsWith('.') ? '$intPart.' : '$intPart.$after';
    } else if (text.length > maxIntegerDigits) {
      text = text.substring(0, maxIntegerDigits);
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Blood pressure: digits and slash only (e.g. 120/80).
class BpInputFormatter extends TextInputFormatter {
  const BpInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 6) text = text.substring(0, 6);
    if (text.length > 3) {
      text = '${text.substring(0, 3)}/${text.substring(3)}';
    } else if (newValue.text.endsWith('/') && text.length <= 3 && text.isNotEmpty) {
      text = '$text/';
    }

    if (newValue.text.contains('/') && !text.contains('/')) {
      final parts = newValue.text.split('/');
      final sys = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
      final dia = parts.length > 1 ? parts[1].replaceAll(RegExp(r'[^0-9]'), '') : '';
      text = '$sys/$dia';
      if (sys.length > 3) text = '${sys.substring(0, 3)}/${sys.substring(3)}$dia';
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
