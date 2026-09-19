import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class BookingStepHeader extends StatelessWidget {
  const BookingStepHeader({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.title,
    this.accentColor = AppColors.patientTeal,
    this.showProgressBar = true,
  });

  final int currentStep;
  final int totalSteps;
  final String title;
  final Color accentColor;
  final bool showProgressBar;

  @override
  Widget build(BuildContext context) {
    final progress = (currentStep + 1) / totalSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(totalSteps, (i) {
            final active = i <= currentStep;
            return Expanded(
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? accentColor : AppColors.cardBgOf(context),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            active ? accentColor : AppColors.borderOf(context),
                      ),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? AppColors.surfaceOf(context)
                            : AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ),
                  if (i < totalSteps - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: i < currentStep
                            ? accentColor
                            : AppColors.borderOf(context),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        if (showProgressBar) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AppColors.borderOf(context),
              color: accentColor,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          title,
          style: GoogleFonts.inter(
              fontSize: AppTypography.headlineSmall,
              fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
