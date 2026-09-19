import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class AppointmentsEmptyState extends StatelessWidget {
  const AppointmentsEmptyState({super.key, required this.tabLabel});

  final String tabLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.doctorBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_busy_outlined,
                size: 56,
                color: AppColors.doctorBlue.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No $tabLabel appointments',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Appointments matching your filters will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyMedium,
                color: AppColors.textSecondaryOf(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
