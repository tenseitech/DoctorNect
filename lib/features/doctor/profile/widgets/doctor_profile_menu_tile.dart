import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class DoctorProfileMenuTile extends StatelessWidget {
  const DoctorProfileMenuTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.iconGradient,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
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
        iconGradient ?? const [AppColors.doctorBlue, Color(0xFF0F4A82)];
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color:
                    AppColors.textSecondaryOf(context).withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
