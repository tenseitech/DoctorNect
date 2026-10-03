import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class PatientPlaceholderScreen extends StatelessWidget {
  const PatientPlaceholderScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppTypography.headlineLarge,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppTypography.bodyMedium,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const Spacer(),
          Center(
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 56,
                  color: AppColors.patientTeal.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Coming soon',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
