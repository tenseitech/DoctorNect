import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';

/// Compact filled add control.
class LabeledAddButton extends StatelessWidget {
  const LabeledAddButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.doctorBlue,
    this.compact = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(Icons.add, size: compact ? 16 : 18),
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: AppColors.white,
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12, vertical: compact ? 6 : 8),
        minimumSize: Size(0, compact ? 32 : 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
