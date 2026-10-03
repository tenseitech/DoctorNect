import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Reusable branded empty state widget for role dashboards (Pharmacy, Lab, Ambulance).
class RoleEmptyState extends StatelessWidget {
  const RoleEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.accentColor,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accentColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppColors.doctorBlue;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16.0 : 24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 64 : 76,
                height: compact ? 64 : 76,
                decoration: BoxDecoration(
                  color: effectiveAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: compact ? 32 : 38,
                  color: effectiveAccent.withValues(alpha: 0.85),
                ),
              ),
              SizedBox(height: compact ? 12 : 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', 
                  fontSize: compact
                      ? AppTypography.bodyLarge
                      : AppTypography.headlineSmall,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', 
                  fontSize: AppTypography.bodySmall,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.4,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: effectiveAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    actionLabel!,
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
