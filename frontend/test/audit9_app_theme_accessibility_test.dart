import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/accessibility/accessibility_tokens.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';

void main() {
  test('AppTheme light applies shared accessibility tap targets', () {
    final theme = AppTheme.light(AppColors.doctorBlue);
    final iconStyle = theme.iconButtonTheme.style;
    expect(
      iconStyle?.minimumSize?.resolve({}),
      const Size(AccessibilityTokens.minTapTarget, AccessibilityTokens.minTapTarget),
    );
    expect(theme.snackBarTheme?.behavior, SnackBarBehavior.floating);
    expect(theme.dialogTheme?.shape, isA<RoundedRectangleBorder>());
  });

  test('AppTheme dark applies shared accessibility tap targets', () {
    final theme = AppTheme.dark(AppColors.doctorBlue);
    final iconStyle = theme.iconButtonTheme.style;
    expect(
      iconStyle?.minimumSize?.resolve({}),
      const Size(AccessibilityTokens.minTapTarget, AccessibilityTokens.minTapTarget),
    );
    expect(theme.focusColor, isNotNull);
  });
}