import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class DoctorScreenTitleBar extends StatelessWidget {
  const DoctorScreenTitleBar({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showBackButton = false,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBackButton;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;

          final titleWidget = Text(
            title,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: isNarrow
                  ? AppTypography.headlineMedium
                  : AppTypography.headlineLarge,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          );

          final subtitleWidget = subtitle != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                )
              : null;

          final backButton = showBackButton
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => Navigator.maybePop(context),
                    child: const Icon(Icons.arrow_back, size: 24),
                  ),
                )
              : null;

          if (isNarrow && trailing != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (backButton != null) backButton,
                    Expanded(child: titleWidget),
                  ],
                ),
                if (subtitleWidget != null) subtitleWidget,
                const SizedBox(height: 12),
                trailing!,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (backButton != null) backButton,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    titleWidget,
                    if (subtitleWidget != null) subtitleWidget,
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 16), trailing!],
            ],
          );
        },
      ),
    );
  }
}
