import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/community_medicine_repository.dart';

class ClinicalSectionCard extends StatefulWidget {
  const ClinicalSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.collapsedSummary,
    this.dense = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool collapsible;
  final bool initiallyExpanded;
  final String? collapsedSummary;
  final bool dense;

  @override
  State<ClinicalSectionCard> createState() => _ClinicalSectionCardState();
}

class _ClinicalSectionCardState extends State<ClinicalSectionCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant ClinicalSectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.collapsible && oldWidget.collapsible) {
      _expanded = true;
    }
  }

  void _toggle() {
    if (!widget.collapsible) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.dense ? 12.0 : 14.0;
    final marginBottom = widget.dense ? 8.0 : 10.0;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: marginBottom),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.collapsible ? _toggle : null,
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, padding - 1, padding, _expanded ? padding - 2 : padding - 1),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: GoogleFonts.inter(
                              fontSize: widget.dense ? 13.5 : 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimaryOf(context),
                              letterSpacing: -0.1,
                            ),
                          ),
                          if (!_expanded && widget.collapsedSummary != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.collapsedSummary!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.trailing != null) widget.trailing!,
                    if (widget.collapsible) ...[
                      if (widget.trailing != null) const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: AppColors.textSecondaryOf(context).withValues(alpha: 0.75),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, thickness: 1, color: AppColors.borderOf(context).withValues(alpha: 0.5)),
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
              child: widget.child,
            ),
          ],
        ],
      ),
    );
  }
}

typedef SuggestionFetcher = List<String> Function(String query);
typedef ItemSuggestionFetcher = List<MedicineSearchSuggestion> Function(String query);

class SearchSuggestionsField extends StatefulWidget {
  const SearchSuggestionsField({
    super.key,
    required this.label,
    required this.controller,
    this.suggestions,
    this.suggestionFetcher,
    this.itemSuggestionFetcher,
    this.hint,
    this.optional = false,
    this.onSelected,
    this.onItemSelected,
    this.maxSuggestionsHeight = 160,
  }) : assert(
          suggestions != null || suggestionFetcher != null || itemSuggestionFetcher != null,
          'Provide suggestions, suggestionFetcher, or itemSuggestionFetcher',
        );

  final String label;
  final TextEditingController controller;
  final List<String>? suggestions;
  final SuggestionFetcher? suggestionFetcher;
  final ItemSuggestionFetcher? itemSuggestionFetcher;
  final String? hint;
  final bool optional;
  final ValueChanged<String>? onSelected;
  final ValueChanged<MedicineSearchSuggestion>? onItemSelected;
  final double maxSuggestionsHeight;

  @override
  State<SearchSuggestionsField> createState() => _SearchSuggestionsFieldState();
}

class _SearchSuggestionsFieldState extends State<SearchSuggestionsField> {
  List<String> _filtered = [];
  List<MedicineSearchSuggestion> _filteredItems = [];
  bool _showSuggestions = false;
  late final FocusNode _focusNode;
  bool get _useItems => widget.itemSuggestionFetcher != null;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  List<String> _runFilter(String query) {
    final fetcher = widget.suggestionFetcher;
    if (fetcher != null) return fetcher(query);
    final list = widget.suggestions ?? const <String>[];
    final q = query.toLowerCase();
    if (q.isEmpty) return list.take(5).toList();
    return list.where((s) => s.toLowerCase().contains(q)).take(8).toList();
  }

  List<MedicineSearchSuggestion> _runItemFilter(String query) {
    final fetcher = widget.itemSuggestionFetcher;
    if (fetcher != null) return fetcher(query);
    return _runFilter(query).map((s) => MedicineSearchSuggestion(name: s)).toList();
  }

  void _onTextChanged() {
    final q = widget.controller.text;
    setState(() {
      if (_useItems) {
        _filteredItems = _runItemFilter(q);
        _showSuggestions = _filteredItems.isNotEmpty;
      } else {
        _filtered = _runFilter(q);
        _showSuggestions = _filtered.isNotEmpty;
      }
    });
  }

  void _selectItem(MedicineSearchSuggestion item) {
    widget.controller.text = item.name;
    widget.onSelected?.call(item.name);
    widget.onItemSelected?.call(item);
    setState(() => _showSuggestions = false);
    _focusNode.unfocus();
  }

  void _closeSuggestions() {
    if (!_showSuggestions) return;
    setState(() => _showSuggestions = false);
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: (_) {
        _closeSuggestions();
        _focusNode.unfocus();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            focusNode: _focusNode,
            controller: widget.controller,
            decoration: InputDecoration(
              labelText: widget.optional ? '${widget.label} (optional)' : widget.label,
              suffixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onTap: () => setState(() {
              if (_useItems) {
                _filteredItems = _runItemFilter(widget.controller.text);
                _showSuggestions = _filteredItems.isNotEmpty;
              } else {
                _filtered = _runFilter(widget.controller.text);
                _showSuggestions = _filtered.isNotEmpty;
              }
            }),
          ),
        if (_showSuggestions && (_useItems ? _filteredItems.isNotEmpty : _filtered.isNotEmpty))
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: BoxConstraints(maxHeight: widget.maxSuggestionsHeight),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(AppConstants.inputRadius),
              border: Border.all(color: AppColors.borderOf(context)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _useItems ? _filteredItems.length : _filtered.length,
              itemBuilder: (context, index) {
                if (_useItems) {
                  final item = _filteredItems[index];
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      title: Text(item.name, style: GoogleFonts.inter(fontSize: 13)),
                      trailing: item.isCommunity
                          ? Text(
                              'Community',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            )
                          : null,
                      onTap: () => _selectItem(item),
                    ),
                  );
                }
                final item = _filtered[index];
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    dense: true,
                    title: Text(item, style: GoogleFonts.inter(fontSize: 13)),
                    onTap: () => _selectItem(MedicineSearchSuggestion(name: item)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

void showClinicalToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF16A34A),
    ),
  );
}
