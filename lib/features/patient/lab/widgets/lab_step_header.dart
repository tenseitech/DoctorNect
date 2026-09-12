import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../booking/widgets/booking_step_header.dart';

class LabStepHeader extends StatelessWidget {
  const LabStepHeader({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.title,
  });

  final int currentStep;
  final int totalSteps;
  final String title;

  @override
  Widget build(BuildContext context) {
    return BookingStepHeader(
      currentStep: currentStep,
      totalSteps: totalSteps,
      title: title,
      accentColor: AppColors.labPurple,
      showProgressBar: false,
    );
  }
}
