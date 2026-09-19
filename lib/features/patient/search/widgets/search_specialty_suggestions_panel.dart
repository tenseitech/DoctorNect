import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../specialty_search_suggestions.dart';
import '../../../../core/theme/app_typography.dart';

class SearchSpecialtySuggestionsPanel extends StatelessWidget {
  const SearchSpecialtySuggestionsPanel({
    super.key,
    required this.suggestions,
    required this.onSelected,
    this.title = 'Speciality recommendations',
  });

  final List<SpecialtySearchSuggestion> suggestions;
  final ValueChanged<SpecialtySearchSuggestion> onSelected;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Material(
      color: AppColors.surfaceOf(context),
      elevation: 0,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderOf(context)),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimaryOf(context).withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryOf(context),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              for (var i = 0; i < suggestions.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.borderOf(context)),
                _SuggestionTile(
                  suggestion: suggestions[i],
                  onTap: () => onSelected(suggestions[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatefulWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
  });

  final SpecialtySearchSuggestion suggestion;
  final VoidCallback onTap;

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered
            ? AppColors.patientTeal.withValues(alpha: 0.06)
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.patientTeal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    s.isCategory
                        ? Icons.category_outlined
                        : Icons.medical_services_outlined,
                    size: 18,
                    color: AppColors.patientTeal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyMedium,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      if (s.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          s.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.north_west_rounded,
                  size: 16,
                  color:
                      AppColors.textSecondaryOf(context).withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
