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
                      final selected = await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => _SearchModalSheet(
                          title: title,
                          initialValue: value,
                          items: items,
                        ),
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

class _SearchModalSheet extends StatefulWidget {
  const _SearchModalSheet({
    required this.title,
    required this.initialValue,
    required this.items,
  });

  final String title;
  final String? initialValue;
  final List<String> items;

  @override
  State<_SearchModalSheet> createState() => _SearchModalSheetState();
}

class _SearchModalSheetState extends State<_SearchModalSheet> {
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
                  w.replaceAll(RegExp(r'[^a-z0-9]'), '').startsWith(cleanQ))))
            return true;

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

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              // Handle bar
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select ${widget.title}',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.headlineSmall,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      color: AppColors.textSecondaryOf(context),
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
                      fontSize: AppTypography.bodyMedium, color: textPrimary),
                  decoration: InputDecoration(
                    hintText:
                        'Type to search ${widget.title.toLowerCase()}... (e.g. maha)',
                    hintStyle: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF0F172A).withValues(alpha: 0.5)
                        : const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),

              // Items List with optional Custom Write-In Entry
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _filteredItems.length +
                      (rawQuery.isNotEmpty && !hasExactMatch ? 1 : 0),
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    if (rawQuery.isNotEmpty && !hasExactMatch && index == 0) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color:
                                AppColors.patientTeal.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add_location_alt_rounded,
                              color: AppColors.patientTeal, size: 18),
                        ),
                        title: Text(
                          'Use "$rawQuery"',
                          style: GoogleFonts.inter(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.patientTeal,
                          ),
                        ),
                        subtitle: Text(
                          'Select custom ${widget.title.toLowerCase()} entry',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                        onTap: () => Navigator.pop(context, rawQuery),
                      );
                    }

                    final itemIndex = rawQuery.isNotEmpty && !hasExactMatch
                        ? index - 1
                        : index;
                    final item = _filteredItems[itemIndex];
                    final isSelected = item == widget.initialValue;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 2),
                      title: Text(
                        item,
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color:
                              isSelected ? AppColors.patientTeal : textPrimary,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.patientTeal,
                              size: 20,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
