import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../../../../core/theme/app_typography.dart';

class PatientFiltersBar extends StatelessWidget {
  const PatientFiltersBar({
    super.key,
    required this.searchController,
    required this.filter,
    required this.sort,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onSortChanged,
    this.onAddWalkIn,
    this.onInviteViaLink,
    this.isLoading = false,
  });

  final TextEditingController searchController;
  final PatientFilter filter;
  final PatientSort sort;
  final VoidCallback onSearchChanged;
  final ValueChanged<PatientFilter> onFilterChanged;
  final ValueChanged<PatientSort> onSortChanged;
  final VoidCallback? onAddWalkIn;
  final VoidCallback? onInviteViaLink;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final wide = !ResponsiveLayout.isCompact(context);

    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 12, wide ? 24 : 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide && (onAddWalkIn != null || onInviteViaLink != null)) ...[
            Row(
              children: [
                if (onAddWalkIn != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isLoading ? null : onAddWalkIn,
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: Text(
                        'Add Walk-in',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.doctorBlue,
                        side: const BorderSide(color: AppColors.doctorBlue),
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (onAddWalkIn != null && onInviteViaLink != null) const SizedBox(width: 10),
                if (onInviteViaLink != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isLoading ? null : onInviteViaLink,
                      icon: const Icon(Icons.link, size: 18),
                      label: Text(
                        'Invite via Link',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.doctorBlue,
                        side: const BorderSide(color: AppColors.doctorBlue),
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          wide ? _buildWideFilters(context) : _buildCompactFilters(context),
        ],
      ),
    );
  }

  Widget _buildCompactFilters(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchField(context),
        const SizedBox(height: 10),
        _filterChips(context),
        const SizedBox(height: 8),
        _sortRow(context),
      ],
    );
  }

  Widget _buildWideFilters(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _searchField(context)),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: _sortRow(context, compact: true)),
          ],
        ),
        const SizedBox(height: 10),
        _filterChips(context),
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    return TextField(
      controller: searchController,
      onChanged: (_) => onSearchChanged(),
      decoration: InputDecoration(
        hintText: 'Search by name or mobile',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  searchController.clear();
                  onSearchChanged();
                },
              )
            : null,
        isDense: true,
        filled: true,
        fillColor: AppColors.cardBgOf(context),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.inputRadius),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.inputRadius),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
      ),
    );
  }

  Widget _filterChips(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: PatientFilter.values.map((f) {
          final label = switch (f) {
            PatientFilter.all => 'All',
            PatientFilter.newPatient => 'New',
            PatientFilter.followUp => 'Follow Up',
            PatientFilter.returning => 'Returning',
            _ => 'Unknown',
};
          final selected = filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label, style: GoogleFonts.inter(fontSize: AppTypography.labelMedium)),
              selected: selected,
              onSelected: (_) => onFilterChanged(f),
              selectedColor: AppColors.doctorBlue.withValues(alpha: 0.15),
              checkmarkColor: AppColors.doctorBlue,
              side: BorderSide(
                color: selected ? AppColors.doctorBlue : AppColors.borderOf(context),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.inputRadius),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sortRow(BuildContext context, {bool compact = false}) {
    return Row(
      children: [
        if (!compact)
          Text('Sort:', style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context))),
        if (!compact) const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<PatientSort>(
            initialValue: sort,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.cardBgOf(context),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.inputRadius),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.inputRadius),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
            ),
            items: const [
              DropdownMenuItem(value: PatientSort.lastVisit, child: Text('Last visit')),
              DropdownMenuItem(value: PatientSort.name, child: Text('Name')),
              DropdownMenuItem(value: PatientSort.appointmentCount, child: Text('Visits')),
            ],
            onChanged: (v) {
              if (v != null) onSortChanged(v);
            },
          ),
        ),
      ],
    );
  }
}
