import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class RecordEmptyState extends StatelessWidget {
  const RecordEmptyState({super.key, required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context) {
    final icon = switch (filter) {
      'Prescription' => AppIcons.prescription,
      'Lab Tests' => Icons.science_outlined,
      'Blood Tests' => Icons.bloodtype_outlined,
      _ => Icons.folder_open_outlined,
    };
    final color = switch (filter) {
      'Blood Tests' => const Color(0xFFDC2626),
      _ => AppColors.patientTeal,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: color.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(
              'No $filter yet',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Shared $filter from your doctor or lab will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  color: AppColors.textSecondaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}
