import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import 'required_field_label.dart';
import '../core/theme/app_typography.dart';

enum _InputMode { list, manual }

// ─────────────────────────────────────────────────────────────────────────────
// Public widget — integrates with Flutter Form (extends FormField<String>)
// ─────────────────────────────────────────────────────────────────────────────

/// Searchable specialization selector that works in both registration forms
/// and profile editing contexts.
///
/// Integrates with Flutter [Form]: place inside a [Form] widget and the
/// field will be included in [FormState.validate] / [FormState.save].
class SpecializationSelector extends FormField<String> {
  SpecializationSelector({
    super.key,
    String? initialValue,
    required void Function(String?) onChanged,
    String label = 'Specialization',
    String placeholder = 'Search or select specialization',
    bool isRequired = false,
    Color accentColor = AppColors.doctorBlue,
    FormFieldValidator<String>? validator,
  }) : super(
          initialValue: initialValue?.trim().isEmpty == true
              ? null
              : initialValue?.trim(),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validator ??
              (isRequired
                  ? (v) => (v == null || v.trim().isEmpty)
                      ? '$label is required'
                      : null
                  : null),
          builder: (state) => _SelectorBody(
            state: state,
            onChanged: onChanged,
            label: label,
            placeholder: placeholder,
            accentColor: accentColor,
            isRequired: isRequired,
          ),
        );
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal body widget
// ─────────────────────────────────────────────────────────────────────────────

class _SelectorBody extends StatefulWidget {
  const _SelectorBody({
    required this.state,
    required this.onChanged,
    required this.label,
    required this.placeholder,
    required this.accentColor,
    required this.isRequired,
  });

  final FormFieldState<String> state;
  final void Function(String?) onChanged;
  final String label;
  final String placeholder;
  final Color accentColor;
  final bool isRequired;

  @override
  State<_SelectorBody> createState() => _SelectorBodyState();
}

class _SelectorBodyState extends State<_SelectorBody> {
  _InputMode _mode = _InputMode.list;
  final _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final v = widget.state.value;
    if (v != null &&
        v.isNotEmpty &&
        !AppConstants.allSpecializations.contains(v)) {
      _mode = _InputMode.manual;
      _manualCtrl.text = v;
    }
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  void _setValue(String? v) {
    final trimmed = v?.trim().isEmpty == true ? null : v?.trim();
    widget.state.didChange(trimmed);
    widget.onChanged(trimmed);
  }

  Future<void> _openPicker() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SpecPickerSheet(
        currentValue: widget.state.value,
        accentColor: widget.accentColor,
      ),
    );
    if (result != null) {
      setState(() => _mode = _InputMode.list);
      _setValue(result);
    }
  }

  void _clear() {
    if (_mode == _InputMode.manual) _manualCtrl.clear();
    _setValue(null);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.state.value;
    final hasValue = value != null && value.isNotEmpty;
    final accent = widget.accentColor;
    final errorText = widget.state.errorText;
    InputDecoration fieldDecoration(InputDecoration decoration) =>
        RequiredFieldLabels.decorate(
          decoration,
          widget.label,
          isRequired: widget.isRequired,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Mode toggle ──────────────────────────────────────────
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeChip(
              label: 'Select from list',
              selected: _mode == _InputMode.list,
              accentColor: accent,
              onTap: () {
                if (_mode != _InputMode.list) {
                  setState(() => _mode = _InputMode.list);
                }
              },
            ),
            const SizedBox(width: 8),
            _ModeChip(
              label: 'Enter manually',
              selected: _mode == _InputMode.manual,
              accentColor: accent,
              onTap: () {
                if (_mode != _InputMode.manual) {
                  setState(() {
                    _mode = _InputMode.manual;
                    _manualCtrl.text = value ?? '';
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Input ────────────────────────────────────────────────
        if (_mode == _InputMode.list)
          InkWell(
            onTap: _openPicker,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: fieldDecoration(
                InputDecoration(
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: widget.placeholder,
                  errorText: errorText,
                  suffixIcon: hasValue
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Clear',
                          onPressed: _clear,
                        )
                      : const Icon(Icons.arrow_drop_down),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: errorText != null
                          ? Theme.of(context).colorScheme.error
                          : Colors.grey.shade400,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accent, width: 2),
                  ),
                ),
              ),
              isEmpty: !hasValue,
              child: hasValue
                  ? Text(value,
                      style: const TextStyle(
                          fontSize: AppTypography.headlineSmall))
                  : const SizedBox.shrink(),
            ),
          )
        else
          TextField(
            controller: _manualCtrl,
            decoration: fieldDecoration(
              InputDecoration(
                hintText: 'e.g. Integrative Medicine',
                errorText: errorText,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: _manualCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _clear,
                      )
                    : null,
              ),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (t) {
              setState(() {});
              _setValue(t);
            },
          ),

        // ── Selected chip ────────────────────────────────────────
        if (hasValue) ...[
          const SizedBox(height: 8),
          Chip(
            label: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
            deleteIcon: Icon(Icons.close, size: 16, color: accent),
            onDeleted: _clear,
            backgroundColor: accent.withValues(alpha: 0.08),
            side: BorderSide(color: accent.withValues(alpha: 0.3)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode toggle chip
// ─────────────────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accentColor : Colors.grey.shade400,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: AppTypography.labelMedium,
            fontWeight: FontWeight.w500,
            color:
                selected ? AppColors.surfaceOf(context) : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SpecPickerSheet extends StatefulWidget {
  const _SpecPickerSheet({this.currentValue, required this.accentColor});

  final String? currentValue;
  final Color accentColor;

  @override
  State<_SpecPickerSheet> createState() => _SpecPickerSheetState();
}

class _SpecPickerSheetState extends State<_SpecPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_ListEntry> _buildEntries() {
    final cats = AppConstants.specializationCategories;
    if (_query.isEmpty) {
      return [
        for (final cat in cats.entries) ...[
          _ListEntry.header(cat.key),
          for (final spec in cat.value) _ListEntry.item(spec),
        ],
      ];
    }
    final q = _query.toLowerCase();
    final result = <_ListEntry>[];
    for (final cat in cats.entries) {
      final matches =
          cat.value.where((s) => s.toLowerCase().contains(q)).toList();
      if (matches.isNotEmpty) {
        result.add(_ListEntry.header(cat.key));
        result.addAll(matches.map(_ListEntry.item));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    final accent = widget.accentColor;
    final itemCount = entries.where((e) => !e.isHeader).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.6, 0.82, 0.95],
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle bar
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select Specialization',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.headlineSmall,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),

              // Search field
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search specializations…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: accent),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: AppColors.cardBgOf(context),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),

              // Result count when searching
              if (_query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$itemCount result${itemCount == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                  ),
                ),

              // List
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off,
                                size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              'No results for "$_query"',
                              style: TextStyle(
                                  color: AppColors.textSecondaryOf(context)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Use "Enter manually" for custom entries',
                              style: TextStyle(
                                  fontSize: AppTypography.labelMedium,
                                  color: AppColors.textSecondaryOf(context)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          if (e.isHeader) {
                            return _CategoryHeader(
                                label: e.text, accentColor: accent);
                          }
                          final isSelected = e.text == widget.currentValue;
                          return ListTile(
                            title: Text(
                              e.text,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.bodyMedium,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected ? accent : null,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_circle,
                                    color: accent, size: 20)
                                : null,
                            tileColor: isSelected
                                ? accent.withValues(alpha: 0.06)
                                : null,
                            onTap: () => Navigator.of(ctx).pop(e.text),
                            dense: true,
                            minVerticalPadding: 10,
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

// ─────────────────────────────────────────────────────────────────────────────
// Category header
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.label, required this.accentColor});

  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      color: accentColor.withValues(alpha: 0.05),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: accentColor,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List entry model
// ─────────────────────────────────────────────────────────────────────────────

class _ListEntry {
  const _ListEntry.header(this.text) : isHeader = true;
  const _ListEntry.item(this.text) : isHeader = false;

  final String text;
  final bool isHeader;
}
