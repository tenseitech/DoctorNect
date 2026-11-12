import 'package:flutter/material.dart';

/// Visual constants from [design/Splash Screen.svg] (1242×2208).
abstract final class SplashDesign {
  static const designCanvasWidth = 1242.0;
  static const designCanvasHeight = 2208.0;

  static const gradientBegin = Alignment(-0.9449, -0.9771);
  static const gradientEnd = Alignment(0.8771, 0.9070);

  static const gradientColors = <Color>[
    Color(0xFF32A5FE),
    Color(0xFF166EFC),
    Color(0xFF0A51EC),
    Color(0xFF001FB3),
  ];

  static const gradientStops = <double>[0.10, 0.31, 0.50, 0.95];

  /// Logo width as a fraction of screen width (612.4 / 1242).
  static const logoWidthFraction = 0.493;

  static const logoAspectWidth = 612.4;
  static const logoAspectHeight = 596.4;

  /// Design-space logo box (for tests).
  static const designLogoLeft = 314.88;
  static const designLogoTop = 806.25;
  static const designLogoWidth = 612.4;
  static const designLogoHeight = 596.4;

  static const logoAssetPath = 'assets/splash/splash_logo.png';
}

/// Splash visual only — no navigation or bootstrap logic.
class SplashDesignView extends StatelessWidget {
  const SplashDesignView({super.key, this.logoKey});

  final Key? logoKey;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final logoWidth = screenWidth * SplashDesign.logoWidthFraction;
    final logoHeight =
        logoWidth * (SplashDesign.logoAspectHeight / SplashDesign.logoAspectWidth);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: SplashDesign.gradientBegin,
          end: SplashDesign.gradientEnd,
          colors: SplashDesign.gradientColors,
          stops: SplashDesign.gradientStops,
        ),
      ),
      child: Center(
        child: SizedBox(
          key: logoKey,
          width: logoWidth,
          height: logoHeight,
          child: Image.asset(
            SplashDesign.logoAssetPath,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
