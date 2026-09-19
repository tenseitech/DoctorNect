import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Material Design 3–aligned typography scale for DoctorNect.
///
/// Sizes are logical pixels; [Text] applies [MediaQuery.textScaler] at render
/// time so accessibility font scaling continues to work.
abstract final class AppTypography {
  // --- Size tokens ---

  /// Hero / marketing display (web brand panel, large stats).
  static const double displayLarge = 24;
  static const double displayMedium = 22;
  static const double displaySmall = 20;

  /// Screen titles ("Enter your mobile number", app bar alternatives).
  static const double headlineLarge = 22;

  /// Section titles, sheet headers, dialog titles.
  static const double headlineMedium = 17;

  /// Card titles, list primary labels.
  static const double headlineSmall = 16;

  static const double titleLarge = 17;
  static const double titleMedium = 16;
  static const double titleSmall = 14;

  static const double bodyLarge = 15;
  static const double bodyMedium = 14;
  static const double bodySmall = 13;

  /// Primary button labels.
  static const double labelLarge = 15;
  static const double labelMedium = 12;
  static const double labelSmall = 11;

  static TextTheme buildTextTheme(TextTheme base) {
    TextStyle token(TextStyle? inherited, double size, FontWeight weight) {
      return GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        height: inherited?.height,
        letterSpacing: inherited?.letterSpacing,
      );
    }

    return GoogleFonts.interTextTheme(base).copyWith(
      displayLarge: token(base.displayLarge, displayLarge, FontWeight.w700),
      displayMedium: token(base.displayMedium, displayMedium, FontWeight.w700),
      displaySmall: token(base.displaySmall, displaySmall, FontWeight.w600),
      headlineLarge: token(base.headlineLarge, headlineLarge, FontWeight.w700),
      headlineMedium:
          token(base.headlineMedium, headlineMedium, FontWeight.w600),
      headlineSmall: token(base.headlineSmall, headlineSmall, FontWeight.w600),
      titleLarge: token(base.titleLarge, titleLarge, FontWeight.w600),
      titleMedium: token(base.titleMedium, titleMedium, FontWeight.w600),
      titleSmall: token(base.titleSmall, titleSmall, FontWeight.w500),
      bodyLarge: token(base.bodyLarge, bodyLarge, FontWeight.w400),
      bodyMedium: token(base.bodyMedium, bodyMedium, FontWeight.w400),
      bodySmall: token(base.bodySmall, bodySmall, FontWeight.w400),
      labelLarge: token(base.labelLarge, labelLarge, FontWeight.w600),
      labelMedium: token(base.labelMedium, labelMedium, FontWeight.w500),
      labelSmall: token(base.labelSmall, labelSmall, FontWeight.w500),
    );
  }

  /// Inter [TextStyle] using a central size token.
  static TextStyle inter({
    required double fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
      decorationColor: decorationColor,
    );
  }
}

extension AppTypographyContext on BuildContext {
  TextTheme get appText => Theme.of(this).textTheme;
}
