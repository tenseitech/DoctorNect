import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Breakpoints for phone / tablet / desktop (web included).
abstract final class ResponsiveLayout {
  static const double compactMaxWidth = 600;
  static const double mediumMaxWidth = 900;

  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) =>
      screenWidth(context) < compactMaxWidth;

  static bool isMedium(BuildContext context) {
    final w = screenWidth(context);
    return w >= compactMaxWidth && w < mediumMaxWidth;
  }

  static bool isExpanded(BuildContext context) =>
      screenWidth(context) >= mediumMaxWidth;

  /// Max width for centered page content (all platforms, all features).
  static double contentMaxWidth(BuildContext context) {
    final w = screenWidth(context);
    if (w < compactMaxWidth) return w;
    if (w < mediumMaxWidth) return 720;
    return 1100;
  }

  static bool get isWeb => kIsWeb;

  static TargetPlatform get platform => defaultTargetPlatform;

  static bool get isMobileNative =>
      !kIsWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
}
