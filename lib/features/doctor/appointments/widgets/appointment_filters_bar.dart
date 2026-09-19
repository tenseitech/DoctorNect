import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/doctor_models.dart';
import '../../../../core/theme/app_typography.dart';

class AppointmentFiltersBar extends StatelessWidget {
  const AppointmentFiltersBar({
    super.key,
    required this.filterDate,
    required this.typeFilter,
    required this.searchController,
    required this.onDateChanged,
    required this.onTypeChanged,
    required this.onSearchChanged,
    this.showDateFilter = true,
  });

  final DateTime? filterDate;
  final AppointmentType? typeFilter;
  final TextEditingController searchController;
  final ValueChanged<DateTime?> onDateChanged;
  final ValueChanged<AppointmentType?> onTypeChanged;
  final VoidCallback onSearchChanged;
  final bool showDateFilter;

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: filterDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.doctorBlue),
        ),
        child: child!,
      ),
    );
    onDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final wide = !ResponsiveLayout.isCompact(context);

    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 12, wide ? 24 : 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: wide ? _buildWideFilters(context) : _buildCompactFilters(context),
    );
  }

  Widget _buildCompactFilters(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _searchField(),
        const SizedBox(height: 10),
        _filterChips(context),
      ],
    );
  }

  Widget _buildWideFilters(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 3, child: _searchField()),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: _filterChips(context)),
      ],
    );
  }

  Widget _searchField() {
    return TextField(
      controller: searchController,
      onChanged: (_) => onSearchChanged(),
      decoration: InputDecoration(
        hintText: 'Search by patient name',
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _filterChips(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (showDateFilter) ...[
            _FilterChip(
              label: filterDate == null
                  ? 'Date'
                  : DateFormat('dd MMM').format(filterDate!),
              icon: Icons.calendar_today_outlined,
              selected: filterDate != null,
              onTap: () => _pickDate(context),
              onClear: filterDate != null ? () => onDateChanged(null) : null,
            ),
            const SizedBox(width: 8),
          ],
          _FilterChip(
            label: typeFilter == null
                ? 'Type: All'
                : typeFilter == AppointmentType.newVisit
                    ? 'New Patient'
                    : typeFilter == AppointmentType.followUp
                        ? 'Follow-up'
                        : 'Returning',
            selected: typeFilter != null,
            onTap: () => _showTypeSheet(context),
            onClear: typeFilter != null ? () => onTypeChanged(null) : null,
          ),
        ],
      ),
    );
  }

  void _showTypeSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All types'),
              onTap: () {
                onTypeChanged(null);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('New Patient'),
              onTap: () {
                onTypeChanged(AppointmentType.newVisit);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Follow-up'),
              onTap: () {
                onTypeChanged(AppointmentType.followUp);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Returning'),
              onTap: () {
                onTypeChanged(AppointmentType.returning);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.onClear,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.doctorBlue.withValues(alpha: 0.12)
          : AppColors.cardBgOf(context),
      borderRadius: BorderRadius.circular(AppConstants.inputRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.inputRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.inputRadius),
            border: Border.all(
              color: selected ? AppColors.doctorBlue : AppColors.borderOf(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? AppColors.doctorBlue : AppColors.textSecondaryOf(context)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  fontWeight: FontWeight.w500,
                  color: selected ? AppColors.doctorBlue : AppColors.textSecondaryOf(context),
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.close, size: 14, color: AppColors.doctorBlue),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
