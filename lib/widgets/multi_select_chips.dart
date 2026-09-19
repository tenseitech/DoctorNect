import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

class MultiSelectChips extends StatelessWidget {
  const MultiSelectChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.accentColor,
    this.errorText,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final Color accentColor;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final isSelected = selected.contains(option);
            return FilterChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (value) {
                final next = Set<String>.from(selected);
                if (value) {
                  next.add(option);
                } else {
                  next.remove(option);
                }
                onChanged(next);
              },
              selectedColor: accentColor.withValues(alpha: 0.15),
              checkmarkColor: accentColor,
              labelStyle: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                color: isSelected ? accentColor : AppColors.textSecondaryOf(context),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              side: BorderSide(
                color: isSelected ? accentColor : AppColors.borderOf(context),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            );
          }).toList(),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.error),
          ),
        ],
      ],
    );
  }
}
