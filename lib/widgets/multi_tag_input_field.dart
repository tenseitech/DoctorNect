import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

typedef TagSuggestionFetcher = List<String> Function(String query);

/// Multi-value text input with optional quick-add chips (doctor/patient forms).
class MultiTagInputField extends StatefulWidget {
  const MultiTagInputField({
    super.key,
    required this.tags,
    required this.onAdd,
    required this.onRemove,
    this.label,
    this.hintText = 'Type and press Add',
    this.quickAddLabels = const [],
    this.quickAddTitle = 'Quick add',
    this.accentColor = AppColors.doctorBlue,
    this.addButtonLabel = 'Add',
    this.maxInputWidth = 260,
    this.suggestionFetcher,
    this.maxSuggestions = 8,
    this.maxSuggestionsHeight = 200,
  });

  final String? label;
  final String hintText;
  final List<String> tags;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final List<String> quickAddLabels;
  final String quickAddTitle;
  final Color accentColor;
  final String addButtonLabel;
  final double maxInputWidth;
  final TagSuggestionFetcher? suggestionFetcher;
  final int maxSuggestions;
  final double maxSuggestionsHeight;

  @override
  State<MultiTagInputField> createState() => _MultiTagInputFieldState();
}

class _MultiTagInputFieldState extends State<MultiTagInputField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<String> _filteredSuggestions = [];
  bool _showSuggestions = false;

  bool get _hasAutocomplete => widget.suggestionFetcher != null;

  @override
  void initState() {
    super.initState();
    if (_hasAutocomplete) {
      _controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    if (_hasAutocomplete) {
      _controller.removeListener(_onTextChanged);
    }
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _currentWord(String text) {
    final lastComma = text.lastIndexOf(',');
    final segment = lastComma >= 0 ? text.substring(lastComma + 1) : text;
    return segment.trim();
  }

  List<String> _runSuggestionFilter(String fullText) {
    final fetcher = widget.suggestionFetcher;
    if (fetcher == null) return const [];

    final query = _currentWord(fullText);
    if (query.isEmpty) return const [];

    final matches = fetcher(query);
    return matches
        .where((name) => !_hasTag(name))
        .take(widget.maxSuggestions)
        .toList();
  }

  void _onTextChanged() {
    final suggestions = _runSuggestionFilter(_controller.text);
    setState(() {
      _filteredSuggestions = suggestions;
      _showSuggestions = suggestions.isNotEmpty && _focusNode.hasFocus;
    });
  }

  void _refreshSuggestions() {
    final suggestions = _runSuggestionFilter(_controller.text);
    setState(() {
      _filteredSuggestions = suggestions;
      _showSuggestions = suggestions.isNotEmpty;
    });
  }

  void _closeSuggestions() {
    if (!_showSuggestions) return;
    setState(() => _showSuggestions = false);
  }

  void _selectSuggestion(String suggestion) {
    _add(suggestion);
    setState(() => _showSuggestions = false);
  }

  bool _hasTag(String value) {
    final key = value.trim().toLowerCase();
    return widget.tags.any((t) => t.toLowerCase() == key);
  }

  void _add(String raw) {
    final value = raw.trim();
    if (value.isEmpty || _hasTag(value)) return;
    widget.onAdd(value);
    _controller.clear();
  }

  String get _addLabel {
    final label = widget.addButtonLabel.trim();
    if (label.startsWith('+')) return label.substring(1).trim();
    return label;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.maxInputWidth),
                child: TapRegion(
                  onTapOutside: (_) => _closeSuggestions(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.surfaceOf(context),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColors.borderOf(context)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColors.borderOf(context)),
                          ),
                        ),
                        onTap: _hasAutocomplete ? _refreshSuggestions : null,
                        onSubmitted: _add,
                      ),
                      if (_hasAutocomplete && _showSuggestions && _filteredSuggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          constraints: BoxConstraints(maxHeight: widget.maxSuggestionsHeight),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceOf(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderOf(context)),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.textPrimaryOf(context).withValues(alpha: 0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _filteredSuggestions.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              thickness: 1,
                              color: AppColors.borderOf(context),
                            ),
                            itemBuilder: (context, index) {
                              final suggestion = _filteredSuggestions[index];
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _selectSuggestion(suggestion),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    child: Text(
                                      suggestion,
                                      style: GoogleFonts.inter(
                                        fontSize: AppTypography.bodySmall,
                                        color: AppColors.textPrimaryOf(context),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => _add(_controller.text),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                _addLabel,
                style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: widget.accentColor,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        if (widget.quickAddLabels.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            widget.quickAddTitle,
            style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.quickAddLabels.map((label) {
              final selected = _hasTag(label);
              return ActionChip(
                label: Text(label, style: GoogleFonts.inter(fontSize: AppTypography.labelMedium)),
                onPressed: selected ? null : () => _add(label),
                backgroundColor: selected
                    ? widget.accentColor.withValues(alpha: 0.15)
                    : AppColors.white,
                side: BorderSide(
                  color: selected ? widget.accentColor : AppColors.borderOf(context),
                ),
              );
            }).toList(),
          ),
        ],
        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.tags.map((tag) {
              return InputChip(
                label: Text(tag, style: GoogleFonts.inter(fontSize: AppTypography.labelMedium)),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => widget.onRemove(tag),
                backgroundColor: widget.accentColor.withValues(alpha: 0.1),
                side: BorderSide(color: widget.accentColor.withValues(alpha: 0.3)),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
