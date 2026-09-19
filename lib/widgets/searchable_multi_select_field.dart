import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';
import 'required_field_label.dart';
import '../core/theme/app_typography.dart';

/// Dropdown-style field that opens a searchable multi-select sheet with checkboxes.
class SearchableMultiSelectField extends StatelessWidget {
  const SearchableMultiSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.accentColor,
    this.placeholder = 'Select options',
    this.searchHint = 'Search...',
    this.errorText,
    this.isRequired = false,
  });

  final String label;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final Color accentColor;
  final String placeholder;
  final String searchHint;
  final String? errorText;
  final bool isRequired;

  String get _summary {
    if (selected.isEmpty) return '';
    final ordered = options.where(selected.contains).toList()
      ..addAll(selected.where((s) => !options.contains(s)));
    if (ordered.length <= 2) return ordered.join(', ');
    return '${ordered.take(2).join(', ')} +${ordered.length - 2} more';
  }

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SearchableMultiSelectSheet(
        title: label,
        options: options,
        initiallySelected: selected,
        searchHint: searchHint,
        accentColor: accentColor,
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = selected.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _openPicker(context),
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: RequiredFieldLabels.decorate(
              InputDecoration(
                errorText: errorText,
                suffixIcon: const Icon(Icons.arrow_drop_down),
                border: const OutlineInputBorder(),
                hintText: placeholder,
                hintStyle: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  color: AppColors.textSecondaryOf(context),
                ),
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              label,
              isRequired: isRequired,
            ),
            isEmpty: !hasSelection,
            child: hasSelection
                ? Text(
                    _summary,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      color: AppColors.textPrimaryOf(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : const SizedBox(height: 24),
          ),
        ),
        if (hasSelection) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: selected.map((item) {
              return Chip(
                label: Text(
                  item,
                  style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: accentColor),
                ),
                deleteIcon: Icon(Icons.close, size: 14, color: accentColor),
                onDeleted: () {
                  final next = Set<String>.from(selected)..remove(item);
                  onChanged(next);
                },
                backgroundColor: accentColor.withValues(alpha: 0.08),
                side: BorderSide(color: accentColor.withValues(alpha: 0.3)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _SearchableMultiSelectSheet extends StatefulWidget {
  const _SearchableMultiSelectSheet({
    required this.title,
    required this.options,
    required this.initiallySelected,
    required this.searchHint,
    required this.accentColor,
  });

  final String title;
  final List<String> options;
  final Set<String> initiallySelected;
  final String searchHint;
  final Color accentColor;

  @override
  State<_SearchableMultiSelectSheet> createState() => _SearchableMultiSelectSheetState();
}

class _SearchableMultiSelectSheetState extends State<_SearchableMultiSelectSheet> {
  late Set<String> _selected;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initiallySelected);
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    if (_query.isEmpty) return widget.options;
    return widget.options.where((o) => o.toLowerCase().contains(_query)).toList();
  }

  void _toggle(String item, bool value) {
    setState(() {
      if (value) {
        _selected.add(item);
      } else {
        _selected.remove(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.headlineSmall,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        if (_selected.isNotEmpty)
                          Text(
                            '${_selected.length} selected',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              color: widget.accentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _searchController.clear,
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No results for "${_searchController.text.trim()}"',
                        style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final item = filtered[index];
                        final isSelected = _selected.contains(item);
                        return InkWell(
                          onTap: () => _toggle(item, !isSelected),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  activeColor: widget.accentColor,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (value) => _toggle(item, value ?? false),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.bodyMedium,
                                      color: AppColors.textPrimaryOf(context),
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
