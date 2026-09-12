import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';

class LabeledRemoveButton extends StatelessWidget {
  const LabeledRemoveButton({
    super.key,
    this.label = 'Remove',
    required this.onPressed,
    this.compact = true,
    this.fullWidth = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool compact;
  final bool fullWidth;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: AppColors.error,
      foregroundColor: AppColors.white,
      disabledBackgroundColor: AppColors.error.withValues(alpha: 0.45),
      disabledForegroundColor: AppColors.white.withValues(alpha: 0.85),
      minimumSize: Size(fullWidth ? double.infinity : 0, compact ? 34 : 48),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 8 : 12,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
      ),
      textStyle: GoogleFonts.inter(
        fontSize: compact ? 12 : 15,
        fontWeight: FontWeight.w600,
      ),
    );

    final Widget button;
    if (icon != null) {
      button = FilledButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: compact ? 16 : 18),
        label: Text(label),
      );
    } else {
      button = FilledButton(
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
