import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../models/lab_models.dart';
import 'lab_test_row.dart';
import '../../../../core/theme/app_typography.dart';

class LabCategoryAccordionSection extends StatelessWidget {
  const LabCategoryAccordionSection({
    super.key,
    required this.groupedTests,
    required this.categoryOrder,
    required this.expandedCategories,
    required this.onToggleCategory,
    required this.onTestTap,
    this.emptyMessage = 'No tests available',
  });

  final Map<String, List<LabTestItem>> groupedTests;
  final List<String> categoryOrder;
  final Set<String> expandedCategories;
  final ValueChanged<String> onToggleCategory;
  final ValueChanged<LabTestItem> onTestTap;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (categoryOrder.isEmpty) {
      return Text(
        emptyMessage,
        style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < categoryOrder.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
          _LabCategoryAccordionPanel(
            title: categoryOrder[i],
            tests: groupedTests[categoryOrder[i]] ?? const [],
            expanded: expandedCategories.contains(categoryOrder[i]),
            onToggle: () => onToggleCategory(categoryOrder[i]),
            onTestTap: onTestTap,
          ),
        ],
      ],
    );
  }
}

class _LabCategoryAccordionPanel extends StatelessWidget {
  const _LabCategoryAccordionPanel({
    required this.title,
    required this.tests,
    required this.expanded,
    required this.onToggle,
    required this.onTestTap,
  });

  final String title;
  final List<LabTestItem> tests;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<LabTestItem> onTestTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: expanded ? AppColors.labPurple.withValues(alpha: 0.04) : AppColors.surfaceOf(context),
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.labPurple,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.labPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${tests.length}',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.labPurple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 22,
                      color: AppColors.textSecondaryOf(context).withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: Duration(milliseconds: 220),
          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: SizedBox(width: double.infinity, height: 0),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
              for (var i = 0; i < tests.length; i++)
                LabTestRow(
                  test: tests[i],
                  showDivider: i < tests.length - 1,
                  onTap: () => onTestTap(tests[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
