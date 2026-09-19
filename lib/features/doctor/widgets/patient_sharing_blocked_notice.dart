import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/patient_sharing_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// Info banner when a registered patient has disabled sharing with doctors.
class PatientSharingBlockedNotice extends StatelessWidget {
  const PatientSharingBlockedNotice({
    super.key,
    this.compact = false,
    this.showSubtitle = true,
  });

  final bool compact;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: compact ? 18 : 20,
            color: const Color(0xFFEA580C),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PatientSharingMessages.dataNotSharedWithDoctors,
                  style: GoogleFonts.inter(
                    fontSize: compact ? 12.5 : 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                    height: 1.35,
                  ),
                ),
                if (showSubtitle) ...[
                  const SizedBox(height: 4),
                  Text(
                    PatientSharingMessages.dataNotSharedSubtitle,
                    style: GoogleFonts.inter(
                      fontSize: compact ? 11.5 : 12,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered empty state for gated clinical lists.
class PatientSharingBlockedEmptyState extends StatelessWidget {
  const PatientSharingBlockedEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_off_outlined,
              size: 48,
              color: AppColors.textSecondaryOf(context).withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              PatientSharingMessages.dataNotSharedWithDoctors,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyLarge,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              PatientSharingMessages.dataNotSharedSubtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}
