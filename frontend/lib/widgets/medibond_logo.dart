import 'dart:ui';

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/asset_resolver.dart';

/// Pure DoctorNect brand mark ('D' + pulse/heartbeat line) with transparent background.
///
/// Designed to seamlessly blend onto dark, gradient, or custom background headers
/// without any square background box or sharp edges.
class DoctorNectMark extends StatelessWidget {
  const DoctorNectMark({
    super.key,
    this.size = 38,
    this.color,
    this.softGlow = true,
  });

  final double size;
  final Color? color;
  final bool softGlow;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    // Mark color: crisp white on dark navy gradient; adjusts subtly with theme
    final markColor =
        color ?? (isDark ? Colors.white : const Color(0xFFF8FAFC));
    final glowColor = isDark
        ? const Color(0xFF14B8A6).withValues(alpha: 0.32)
        : const Color(0xFF38BDF8).withValues(alpha: 0.28);

    final imageWidget = Image.asset(
      AssetResolver.resolve('assets/images/logo_mark_transparent.png'),
      height: size,
      fit: BoxFit.contain,
      color: markColor,
      errorBuilder: (_, __, ___) => Icon(
        Icons.local_hospital_rounded,
        size: size,
        color: markColor,
      ),
    );

    if (!softGlow) {
      return imageWidget;
    }

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Image.asset(
            AssetResolver.resolve('assets/images/logo_mark_transparent.png'),
            height: size,
            fit: BoxFit.contain,
            color: glowColor,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        imageWidget,
      ],
    );
  }
}

class DoctorNectLogo extends StatelessWidget {
  const DoctorNectLogo({
    super.key,
    this.size = 72,
    this.transparent = false,
    this.softGlow = false,
    this.color,
  });

  final double size;
  final bool transparent;
  final bool softGlow;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (transparent) {
      return DoctorNectMark(
        size: size,
        color: color,
        softGlow: softGlow,
      );
    }
    // Full brand mark includes icon + "DoctorNect" wordmark.
    final height = size * 1.15;
    return Image.asset(
      'assets/images/logo.webp',
      width: size * 1.4,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.practoTeal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(size * 0.22),
            ),
            child: Icon(
              Icons.local_hospital_rounded,
              size: size * 0.55,
              color: AppColors.practoTeal,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'DoctorNect',
            style: TextStyle(
              fontSize: size * 0.38,
              fontWeight: FontWeight.w700,
              color: AppColors.practoTeal,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// DoctorNect branding for desktop/web side rails — hidden on mobile shells.
class SidebarDoctorNectLogo extends StatelessWidget {
  const SidebarDoctorNectLogo({super.key, this.extended = true});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        extended ? 'DoctorNect' : 'DN',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: extended ? 20 : 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          height: 1.1,
          color: AppColors.textPrimaryOf(context),
        ),
      ),
    );
  }
}
