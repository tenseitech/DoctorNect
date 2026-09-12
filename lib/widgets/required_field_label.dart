import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Label with a red asterisk for mandatory form fields.
class RequiredFieldLabel extends StatelessWidget {
  const RequiredFieldLabel(
    this.text, {
    super.key,
    this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ??
        Theme.of(context).inputDecorationTheme.labelStyle ??
        DefaultTextStyle.of(context).style;

    return Text.rich(
      TextSpan(
        text: text,
        style: baseStyle,
        children: [
          TextSpan(
            text: ' *',
            style: baseStyle.merge(const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Helpers for applying required-field labels across the app.
abstract final class RequiredFieldLabels {
  /// Strips a trailing ` *` from legacy label strings.
  static String clean(String label) => label.replaceFirst(RegExp(r'\s*\*$'), '');

  static InputDecoration decorate(
    InputDecoration decoration,
    String label, {
    bool isRequired = false,
  }) {
    final text = clean(label);
    if (!isRequired) {
      return decoration.copyWith(
        labelText: text.isNotEmpty ? text : null,
        label: null,
      );
    }
    return decoration.copyWith(
      labelText: null,
      label: text.isNotEmpty ? RequiredFieldLabel(text, style: decoration.labelStyle) : null,
    );
  }

  static Widget text(
    String label, {
    bool isRequired = false,
    TextStyle? style,
  }) {
    final text = clean(label);
    if (!isRequired) return Text(text, style: style);
    return RequiredFieldLabel(text, style: style);
  }
}
