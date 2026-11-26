import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';

/// WCAG 2.2 relative luminance contrast ratio (Audit 9 / closure UX-16).
double contrastRatio(Color a, Color b) {
  double linearize(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double lum(Color c) {
    final r = linearize(c.r);
    final g = linearize(c.g);
    final b = linearize(c.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  final l1 = lum(a);
  final l2 = lum(b);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  const aaNormal = 4.5;
  const aaLarge = 3.0;

  test('light theme primary text on white meets WCAG AA', () {
    expect(
      contrastRatio(AppColors.textPrimary, AppColors.white),
      greaterThanOrEqualTo(aaNormal),
    );
  });

  test('light theme secondary text on white meets WCAG AA for large text', () {
    expect(
      contrastRatio(AppColors.textSecondary, AppColors.white),
      greaterThanOrEqualTo(aaLarge),
    );
  });

  test('light theme error on white meets WCAG AA', () {
    expect(
      contrastRatio(AppColors.error, AppColors.white),
      greaterThanOrEqualTo(aaNormal),
    );
  });

  test('dark theme primary text on dark surface meets WCAG AA', () {
    expect(
      contrastRatio(AppColors.darkTextPrimary, AppColors.darkSurface),
      greaterThanOrEqualTo(aaNormal),
    );
  });

  test('doctorBlue on white button label contrast (onPrimary)', () {
    expect(
      contrastRatio(AppColors.white, AppColors.doctorBlue),
      greaterThanOrEqualTo(aaNormal),
    );
  });
}