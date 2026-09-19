import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class RecordsTabSummary extends StatelessWidget {
  const RecordsTabSummary({
    super.key,
    required this.icon,
    required this.count,
    required this.label,
    required this.hint,
    required this.accentColor,
  });

  final IconData icon;
  final int count;
  final String label;
  final String hint;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final countLabel = count == 1 ? '1 $label' : '$count ${label}s';

    return ColoredBox(
      color: accentColor.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    countLabel,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyLarge,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecordsTabStyle {
  const RecordsTabStyle({
    required this.accentColor,
    required this.icon,
    required this.summaryLabel,
    required this.summaryHint,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final Color accentColor;
  final IconData icon;
  final String summaryLabel;
  final String summaryHint;
  final String emptyTitle;
  final String emptyMessage;

  static RecordsTabStyle forLabel(String tabLabel) {
    return switch (tabLabel) {
      'Prescription' => const RecordsTabStyle(
          accentColor: AppColors.doctorBlue,
          icon: AppIcons.prescription,
          summaryLabel: 'prescription',
          summaryHint: 'Shared by your doctor after consultation',
          emptyTitle: 'No prescriptions yet',
          emptyMessage: 'Prescriptions from your doctor will appear here.',
        ),
      'Lab Tests' => const RecordsTabStyle(
          accentColor: AppColors.patientTeal,
          icon: Icons.science_outlined,
          summaryLabel: 'lab test',
          summaryHint: 'Orders and reports from clinic or lab',
          emptyTitle: 'No lab tests yet',
          emptyMessage: 'Lab test orders from your doctor will show up here.',
        ),
      'Tests' => const RecordsTabStyle(
          accentColor: AppColors.patientTeal,
          icon: Icons.science_outlined,
          summaryLabel: 'test',
          summaryHint: 'Lab orders, bookings and reports from your doctor or partner labs',
          emptyTitle: 'No tests yet',
          emptyMessage: 'Lab test orders and blood test bookings will appear here.',
        ),
      'Blood Tests' => const RecordsTabStyle(
          accentColor: Color(0xFFDC2626),
          icon: Icons.bloodtype_outlined,
          summaryLabel: 'blood test',
          summaryHint: 'Bookings and reports from partner labs',
          emptyTitle: 'No blood tests yet',
          emptyMessage: 'Blood test bookings and reports will appear here.',
        ),
      _ => const RecordsTabStyle(
          accentColor: AppColors.patientTeal,
          icon: Icons.folder_open_outlined,
          summaryLabel: 'record',
          summaryHint: 'Your medical documents',
          emptyTitle: 'No records yet',
          emptyMessage: 'Records shared with you will appear here.',
        ),
    };
  }
}
