import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../models/lab_models.dart';
import '../../../../core/theme/app_typography.dart';

class LabTestRow extends StatelessWidget {
  const LabTestRow({
    super.key,
    required this.test,
    required this.onTap,
    this.showDivider = false,
  });

  final LabTestItem test;
  final VoidCallback onTap;
  final bool showDivider;

  static ({IconData icon, Color color}) _sampleStyle(SampleType type) {
    return switch (type) {
      SampleType.blood => (
          icon: Icons.bloodtype_outlined,
          color: const Color(0xFFDC2626),
        ),
      SampleType.urine => (
          icon: Icons.water_drop_outlined,
          color: const Color(0xFF2563EB),
        ),
      SampleType.stool => (
          icon: Icons.science_outlined,
          color: const Color(0xFFD97706),
        ),
    };
  }

  static String _sampleLabel(SampleType type) {
    return switch (type) {
      SampleType.blood => 'Blood',
      SampleType.urine => 'Urine',
      SampleType.stool => 'Stool',
    };
  }

  static String _metaLine(LabTestItem test) {
    return [
      if (test.fastingRequired) 'Fasting' else 'No fasting',
      '${test.reportHours}h report',
      _sampleLabel(test.sampleType),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final style = _sampleStyle(test.sampleType);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppColors.surfaceOf(context),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: style.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(style.icon, color: style.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          test.name,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: AppTypography.bodyMedium,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _metaLine(test),
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textSecondaryOf(context)
                        .withValues(alpha: 0.75),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
      ],
    );
  }
}
