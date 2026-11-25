import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Visual constants shared with the native splash (see pubspec.yaml
/// `flutter_native_splash` and tools/generate_brand_assets.js).
///
/// The native splash (pre-Android 12, Android 12+ and iOS) shows the mark at
/// [logoWidthDp] on a solid [background], centred in the window. The Flutter
/// splash draws exactly the same thing, so the hand-off is invisible: no colour
/// jump, no resize and no white flash, in light and dark mode.
abstract final class SplashDesign {
  /// Same value as `color` / `color_dark` in the native splash config.
  static const Color background = AppColors.doctorBlue;

  /// Mark width in logical pixels (dp). Must match SPLASH_MARK_DP in
  /// tools/generate_brand_assets.js.
  static const double logoWidthDp = 134;

  /// Width / height of the mark (from the vector master's bounding box).
  static const double logoAspectRatio = 1.1079;

  static double get logoHeightDp => logoWidthDp / logoAspectRatio;

  /// Tight 4x raster of the vector mark (536 px wide).
  static const logoAssetPath = 'assets/splash/splash_mark.png';
}

/// Splash visual only — no navigation or bootstrap logic.
class SplashDesignView extends StatelessWidget {
  const SplashDesignView({super.key, this.logoKey});

  final Key? logoKey;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SplashDesign.background,
      child: Center(
        child: SizedBox(
          key: logoKey,
          width: SplashDesign.logoWidthDp,
          height: SplashDesign.logoHeightDp,
          child: Image.asset(
            SplashDesign.logoAssetPath,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            semanticLabel: 'DoctorNect',
          ),
        ),
      ),
    );
  }
}
