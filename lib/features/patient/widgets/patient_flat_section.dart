import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import 'patient_screen_title_bar.dart';

/// Flat section band — matches patient home Explore / Services style.
class PatientFlatSection extends StatelessWidget {
  const PatientFlatSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.shaded = false,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool shaded;
  final Widget? trailing;

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Shell tab header with title + tab bar + divider.
class PatientShellTabHeader extends StatelessWidget {
  const PatientShellTabHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.tabBar,
  });

  final String title;
  final String? subtitle;
  final TabBar tabBar;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PatientScreenTitleBar(title: title, subtitle: subtitle),
          tabBar,
          Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
        ],
      ),
    );
  }
}
