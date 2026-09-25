import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
    this.iconGradient,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;
  final List<Color>? iconGradient;

  /// Blends the base color for dark and light theme stroke icons.
  static Color resolveStrokeColor(Color base, bool isDark) {
    if (!isDark) {
      final hsl = HSLColor.fromColor(base);
      if (hsl.lightness > 0.55) {
        return hsl.withLightness(0.44).toColor();
      }
      return base;
    }
    // In dark mode, soften and lighten the color so it harmoniously blends
    // with the dark background without harsh contrast or eye strain.
    final hsl = HSLColor.fromColor(base);
    final blendedLightness = (hsl.lightness < 0.60) ? 0.68 : hsl.lightness;
    final blendedSaturation = (hsl.saturation * 0.82).clamp(0.35, 0.90);
    return hsl
        .withLightness(blendedLightness)
        .withSaturation(blendedSaturation)
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient =
        iconGradient ?? const [Color(0xFF0D9488), Color(0xFF0369A1)];
    final strokeColor = resolveStrokeColor(gradient.first, isDark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Icon(
                    icon,
                    size: 22,
                    color: strokeColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textSecondaryOf(context)
                        .withValues(alpha: 0.85),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Legacy header — prefer [ProfileSectionCard].
class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: AppTypography.bodySmall,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondaryOf(context),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
