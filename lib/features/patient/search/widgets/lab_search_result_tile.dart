import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

enum LabSearchResultKind { test, package, lab }

class LabSearchResultTile extends StatelessWidget {
  const LabSearchResultTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.onTap,
    this.showDivider = false,
  });

  final String title;
  final String subtitle;
  final LabSearchResultKind kind;
  final VoidCallback onTap;
  final bool showDivider;

  IconData get _icon => switch (kind) {
        LabSearchResultKind.test => Icons.science_outlined,
        LabSearchResultKind.package => Icons.local_offer_outlined,
        LabSearchResultKind.lab => Icons.biotech_outlined,
      };

  Color get _color => switch (kind) {
        LabSearchResultKind.test => AppColors.labPurple,
        LabSearchResultKind.package => const Color(0xFF7C3AED),
        LabSearchResultKind.lab => AppColors.patientTeal,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppColors.surfaceOf(context),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_icon, color: _color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textSecondaryOf(context).withValues(alpha: 0.75),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
      ],
    );
  }
}

class LabSearchSectionHeader extends StatelessWidget {
  const LabSearchSectionHeader({
    super.key,
    required this.title,
    required this.count,
    this.accentColor = AppColors.labPurple,
  });

  final String title;
  final int count;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.cardBgOf(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 14,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
            Text(
              '$count',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
