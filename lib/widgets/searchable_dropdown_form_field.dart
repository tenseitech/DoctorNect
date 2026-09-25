import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

class SearchableDropdownFormField extends FormField<String> {
  SearchableDropdownFormField({
    super.key,
    required String title,
    required String? value,
    required List<String> items,
    required ValueChanged<String?>? onChanged,
    InputDecoration? decoration,
    String? hintText,
    super.validator,
    super.enabled = true,
  }) : super(
          initialValue: value,
          builder: (FormFieldState<String> state) {
            final context = state.context;
            final effectiveDecoration =
                (decoration ?? const InputDecoration()).copyWith(
              errorText: state.errorText,
            );

            final displayValue =
                value != null && value.isNotEmpty ? value : null;

            return InkWell(
              onTap: enabled
                  ? () async {
                      final selected = await SearchableDropdownModalSheet.show(
                        context,
                        title: title,
                        initialValue: value,
                        items: items,
                      );

                      if (selected != null) {
                        state.didChange(selected);
                        onChanged?.call(selected);
                      }
                    }
                  : null,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: effectiveDecoration.copyWith(
                  suffixIcon: Icon(
                    Icons.arrow_drop_down_rounded,
                    color: enabled
                        ? AppColors.textSecondaryOf(context)
                        : AppColors.textSecondaryOf(context)
                            .withValues(alpha: 0.4),
                  ),
                ),
                isEmpty: false,
                child: Text(
                  displayValue ?? hintText ?? 'Select $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    color: displayValue != null
                        ? AppColors.textPrimaryOf(context)
                        : AppColors.textSecondaryOf(context)
                            .withValues(alpha: enabled ? 0.75 : 0.4),
                  ),
                ),
              ),
            );
          },
        );
}

class SearchableDropdownModalSheet extends StatefulWidget {
  const SearchableDropdownModalSheet({
    super.key,
    required this.title,
    required this.initialValue,
    required this.items,
  });

  final String title;
  final String? initialValue;
  final List<String> items;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String? initialValue,
    required List<String> items,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SearchableDropdownModalSheet(
        title: title,
        initialValue: initialValue,
        items: items,
      ),
    );
  }

  @override
  State<SearchableDropdownModalSheet> createState() =>
      _SearchableDropdownModalSheetState();
}

typedef _SearchModalSheet = SearchableDropdownModalSheet;

class _SearchableDropdownModalSheetState
    extends State<SearchableDropdownModalSheet> {
  late final TextEditingController _searchController;
  late List<String> _filteredItems;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredItems = List.from(widget.items);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final rawQ = query.trim();
    final q = rawQ.toLowerCase();

    setState(() {
      if (q.isEmpty) {
        _filteredItems = List.from(widget.items);
      } else {
        final cleanQ = q.replaceAll(RegExp(r'[^a-z0-9]'), '');

        final matched = widget.items.where((item) {
          final itemLower = item.toLowerCase();
          final cleanItem = itemLower.replaceAll(RegExp(r'[^a-z0-9]'), '');

          // 1. Direct contains / startsWith
          if (itemLower.contains(q) || cleanItem.contains(cleanQ)) return true;

          // 2. Word start match (e.g. "maha" matches "Maharashtra")
          final words = itemLower.split(RegExp(r'[\s\-_,]+'));
          if (words.any((w) =>
              w.startsWith(q) ||
              (cleanQ.isNotEmpty &&
                  w.replaceAll(RegExp(r'[^a-z0-9]'), '').startsWith(cleanQ)))) {
            return true;
          }

          return false;
        }).toList();

        // Sort: items starting with query first!
        matched.sort((a, b) {
          final aLower = a.toLowerCase();
          final bLower = b.toLowerCase();
          final aStarts = aLower.startsWith(q);
          final bStarts = bLower.startsWith(q);
          if (aStarts && !bStarts) return -1;
          if (!aStarts && bStarts) return 1;
          return aLower.compareTo(bLower);
        });

        _filteredItems = matched;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final rawQuery = _searchController.text.trim();
    final hasExactMatch = _filteredItems
        .any((item) => item.toLowerCase() == rawQuery.toLowerCase());
    final hasCustomTile = rawQuery.isNotEmpty && !hasExactMatch;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                children: [
                  // Handle bar
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Select ${widget.title}',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 22),
                          onPressed: () => Navigator.pop(context),
                          color: AppColors.textSecondaryOf(context),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),
                  // Search Bar
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      onChanged: _onSearchChanged,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        color: textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Type to search ${widget.title.toLowerCase()}... (e.g. maha)',
                        hintStyle: GoogleFonts.inter(
                          fontSize: AppTypography.bodyMedium,
                          color: AppColors.textSecondaryOf(context)
                              .withValues(alpha: 0.7),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon:
                                    const Icon(Icons.cancel_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF0F172A).withValues(alpha: 0.45)
                            : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : const Color(0xFFE2E8F0),
                            width: 1.0,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : const Color(0xFFE2E8F0),
                            width: 1.0,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppColors.patientTeal,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Items List with optional Custom Write-In Entry
                  Expanded(
                    child: _filteredItems.isEmpty && !hasCustomTile
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.location_off_outlined,
                                    size: 44,
                                    color: AppColors.textSecondaryOf(context)
                                        .withValues(alpha: 0.4),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No results found',
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.bodyMedium,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Try searching with a different keyword',
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.labelMedium,
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount:
                                _filteredItems.length + (hasCustomTile ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (hasCustomTile && index == 0) {
                                return _buildCustomWriteInTile(
                                  context: context,
                                  query: rawQuery,
                                  onTap: () => Navigator.pop(context, rawQuery),
                                  isDark: isDark,
                                );
                              }

                              final itemIndex =
                                  hasCustomTile ? index - 1 : index;
                              final item = _filteredItems[itemIndex];
                              final isSelected = item == widget.initialValue;

                              return _buildItemTile(
                                context: context,
                                text: item,
                                isSelected: isSelected,
                                onTap: () => Navigator.pop(context, item),
                                isDark: isDark,
                                textPrimary: textPrimary,
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildItemTile({
    required BuildContext context,
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    required Color textPrimary,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2.5),
      child: Material(
        color: isSelected
            ? AppColors.patientTeal.withValues(alpha: 0.09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: AppColors.patientTeal.withValues(alpha: 0.06),
          splashColor: AppColors.patientTeal.withValues(alpha: 0.12),
          highlightColor: AppColors.patientTeal.withValues(alpha: 0.08),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.patientTeal.withValues(alpha: 0.35)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.035)),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? AppColors.patientTeal : textPrimary,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.patientTeal,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomWriteInTile({
    required BuildContext context,
    required String query,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: AppColors.patientTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: AppColors.patientTeal.withValues(alpha: 0.12),
          splashColor: AppColors.patientTeal.withValues(alpha: 0.18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.patientTeal.withValues(alpha: 0.3),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.patientTeal.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_location_alt_rounded,
                    color: AppColors.patientTeal,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Use "$query"',
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.patientTeal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select custom ${widget.title.toLowerCase()} entry',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppColors.patientTeal,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
