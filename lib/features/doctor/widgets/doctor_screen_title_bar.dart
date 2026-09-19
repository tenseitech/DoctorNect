import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class DoctorScreenTitleBar extends StatelessWidget {
  const DoctorScreenTitleBar({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showBackButton = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showBackButton) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => Navigator.maybePop(context),
                    child: const Icon(Icons.arrow_back, size: 24),
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineLarge,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
