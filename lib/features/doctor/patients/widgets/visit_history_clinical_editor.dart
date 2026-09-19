import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

const _observationGreen = Color(0xFF16A34A);

/// Read-only chief complaints + observations on patient visit history cards.
class VisitHistoryClinicalEditor extends StatelessWidget {
  const VisitHistoryClinicalEditor({
    super.key,
    required this.initialChiefComplaints,
    required this.initialObservations,
  });

  final List<String> initialChiefComplaints;
  final List<String> initialObservations;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: 'Chief Complaints', color: AppColors.doctorBlue),
        const SizedBox(height: 6),
        _ReadOnlyTagList(
          items: initialChiefComplaints,
          emptyLabel: 'No chief complaints recorded',
          accent: AppColors.doctorBlue,
        ),
        const SizedBox(height: 14),
        _SectionHeader(title: 'Observations', color: _observationGreen),
        const SizedBox(height: 6),
        _ReadOnlyTagList(
          items: initialObservations,
          emptyLabel: 'No observations recorded',
          accent: _observationGreen,
        ),
      ],
    );
  }
}

class _ReadOnlyTagList extends StatelessWidget {
  const _ReadOnlyTagList({
    required this.items,
    required this.emptyLabel,
    required this.accent,
  });

  final List<String> items;
  final String emptyLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        emptyLabel,
        style: GoogleFonts.inter(
          fontSize: AppTypography.bodySmall,
          color: AppColors.textSecondaryOf(context),
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Text(
            item,
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: AppTypography.labelMedium,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
