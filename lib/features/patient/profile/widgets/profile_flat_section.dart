import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';

/// Flat profile section — matches patient home Explore/Services bands.
class ProfileFlatSection extends StatelessWidget {
  const ProfileFlatSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.shaded = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final isWide = !ResponsiveLayout.isCompact(context);

    return ColoredBox(
      color: shaded ? AppColors.cardBgOf(context) : AppColors.surfaceOf(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isWide ? 20 : 16,
          isWide ? 18 : 14,
          isWide ? 20 : 16,
          isWide ? 16 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: isWide ? 17 : 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: GoogleFonts.inter(
                  fontSize: isWide ? 13 : 12,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Legacy name — same flat section.
typedef ProfileSectionCard = ProfileFlatSection;
