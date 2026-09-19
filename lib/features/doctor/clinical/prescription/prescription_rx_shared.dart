import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/clinical_mock_data.dart';
import '../data/dosage_units.dart';
import '../data/community_medicine_repository.dart';
import '../models/clinical_models.dart';
import '../widgets/clinical_input_formatters.dart';
import '../../../../core/theme/app_typography.dart';

List<MedicineEntry> namedMedicineEntries(List<MedicineEntry> medicines) =>
    medicines.where((m) => m.name.trim().isNotEmpty).toList();

/// Fixed-height workspace for Rx list + catalog so the page does not grow with each medicine.
double rxWorkspaceHeight(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  return (h * 0.48).clamp(260.0, 460.0);
}

/// Shown when no medicines have been added yet.
class RxEmptyState extends StatelessWidget {
  const RxEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            AppIcons.prescription,
            size: 28,
            color: AppColors.textSecondaryOf(context).withValues(alpha: 0.7),
          ),
          const SizedBox(height: 8),
          Text(
            'Search above to add medicines',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared search bar for Rx medicine picker.
class RxMedicineSearchBar extends StatelessWidget {
  const RxMedicineSearchBar({
    super.key,
    required this.controller,
    required this.searchQuery,
    required this.results,
    required this.showResults,
    required this.onChanged,
    required this.onSelect,
    this.trailing,
    this.maxWidth,
  });

  final TextEditingController controller;
  final String searchQuery;
  final List<MedicineSearchSuggestion> results;
  final bool showResults;
  final ValueChanged<String> onChanged;
  final ValueChanged<MedicineSearchSuggestion> onSelect;
  final Widget? trailing;
  final double? maxWidth;

  static String _formatSuggestion(MedicineSearchSuggestion item) {
    final form = (item.form ?? 'Tablet').toUpperCase();
    return '$form · ${item.name}';
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium),
                decoration: InputDecoration(
                  labelText: 'Search & add medicine',
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.doctorBlue.withValues(alpha: 0.85)),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            controller.clear();
                            onChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.cardBgOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.doctorBlue, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: onChanged,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
        if (showResults)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderOf(context)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      child: Text(
                        'No medicines found',
                        style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
                      ),
                    )
                  : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 12, endIndent: 12),
                    itemBuilder: (context, i) {
                      final item = results[i];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.doctorBlue.withValues(alpha: 0.1),
                          child: Icon(AppIcons.prescription, size: 16, color: AppColors.doctorBlue),
                        ),
                        title: Text(
                          item.name,
                          style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _formatSuggestion(item),
                          style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                        ),
                        trailing: Icon(Icons.add_circle_outline, size: 20, color: AppColors.doctorBlue),
                        onTap: () => onSelect(item),
                      );
                    },
                  ),
            ),
          ),
      ],
    );

    if (maxWidth == null) return content;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: content,
      ),
    );
  }
}

/// Card layout for a single medicine line in Rx.
class RxMedicineCard extends StatefulWidget {
  const RxMedicineCard({
    super.key,
    required this.index,
    required this.entry,
    required this.nameController,
    required this.isExpanded,
    required this.showInstruction,
    required this.canDelete,
    required this.onExpandToggle,
    required this.onToggleInstruction,
    required this.onDelete,
    required this.onChanged,
    required this.onConfirm,
  });

  final int index;
  final MedicineEntry entry;
  final TextEditingController nameController;
  final bool isExpanded;
  final bool showInstruction;
  final bool canDelete;
  final VoidCallback onExpandToggle;
  final VoidCallback onToggleInstruction;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final VoidCallback onConfirm;

  @override
  State<RxMedicineCard> createState() => _RxMedicineCardState();
}

class _RxMedicineCardState extends State<RxMedicineCard> {
  late final TextEditingController _strengthController;
  late final TextEditingController _durationController;
  late final TextEditingController _qtyController;
  late final TextEditingController _specialInstructionsController;

  MedicineEntry get entry => widget.entry;

  List<String> get _dosageUnits => dosageUnitsIncluding(entry.dosageUnit);

  @override
  void initState() {
    super.initState();
    _strengthController = TextEditingController(text: entry.dosageAmount);
    _durationController = TextEditingController(text: entry.durationAmount);
    _qtyController = TextEditingController(text: entry.quantity);
    _specialInstructionsController = TextEditingController(text: entry.specialInstructions);
  }

  @override
  void dispose() {
    _strengthController.dispose();
    _durationController.dispose();
    _qtyController.dispose();
    _specialInstructionsController.dispose();
    super.dispose();
  }

  void _refreshAutoQuantity() {
    entry.recalculateQuantity();
    final nextQty = entry.quantity;
    if (_qtyController.text != nextQty) {
      _qtyController.text = nextQty;
    }
  }

  void _handleConfirm() {
    _refreshAutoQuantity();
    widget.onChanged();
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onConfirm();
  }

  InputDecoration _fieldDecoration({String? label}) => InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceOf(context),
        labelStyle: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
      );

  Widget _freqChip({
    required String label,
    required String short,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.doctorBlue : AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            onSelected(!selected);
            entry.useCustomFrequency = false;
            _refreshAutoQuantity();
            setState(() {});
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.doctorBlue : AppColors.borderOf(context),
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  short,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.surfaceOf(context) : AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: selected ? AppColors.surfaceOf(context).withValues(alpha: 0.9) : AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _freqBadge(String label, bool active) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? AppColors.doctorBlue : AppColors.borderOf(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: active ? AppColors.surfaceOf(context) : AppColors.textSecondaryOf(context),
        ),
      ),
    );
  }

  Widget _buildCollapsedHeader() {
    final dosage = entry.dosageLabel;
    final duration = entry.durationLabel;
    final freq = entry.frequencyLabel;

    return Material(
      color: widget.isExpanded ? AppColors.doctorBlue.withValues(alpha: 0.04) : AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: widget.onExpandToggle,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.isExpanded
                      ? AppColors.doctorBlue
                      : AppColors.doctorBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${widget.index + 1}',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: widget.isExpanded ? AppColors.surfaceOf(context) : AppColors.doctorBlue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.nameController,
                  builder: (context, value, _) {
                    final displayName = entry.name.trim().isNotEmpty
                        ? entry.name.trim()
                        : value.text.trim();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        if (!widget.isExpanded) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (dosage.isNotEmpty)
                                Text(
                                  dosage,
                                  style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                                ),
                              if (dosage.isNotEmpty && duration.isNotEmpty)
                                Text(
                                  ' · ',
                                  style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                                ),
                              if (duration.isNotEmpty)
                                Text(
                                  duration,
                                  style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                                ),
                              if (entry.isSos) ...[
                                const SizedBox(width: 6),
                                Text(
                                  'SOS',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ] else if (entry.form.isNotEmpty)
                          Text(
                            entry.form,
                            style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (!widget.isExpanded) ...[
                _freqBadge('M', entry.morning),
                const SizedBox(width: 3),
                _freqBadge('A', entry.afternoon),
                const SizedBox(width: 3),
                _freqBadge('N', entry.night),
                const SizedBox(width: 6),
                if (freq == 'As directed')
                  Text(
                    freq,
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondaryOf(context)),
                  ),
              ],
              Icon(
                widget.isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 20,
                color: AppColors.textSecondaryOf(context),
              ),
              IconButton(
                onPressed: widget.canDelete ? widget.onDelete : null,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: widget.canDelete ? AppColors.textSecondaryOf(context) : AppColors.borderOf(context),
                ),
                tooltip: 'Remove medicine',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isExpanded
              ? AppColors.doctorBlue.withValues(alpha: 0.45)
              : AppColors.borderOf(context),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCollapsedHeader(),
          if (widget.isExpanded)
            Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _strengthController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: const [
                          DecimalInputFormatter(maxIntegerDigits: 4, maxDecimalDigits: 2),
                        ],
                        style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                        decoration: _fieldDecoration(label: 'Strength'),
                        onChanged: (v) => entry.dosageAmount = v,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _dosageUnits.contains(entry.dosageUnit)
                            ? entry.dosageUnit
                            : _dosageUnits.first,
                        isExpanded: true,
                        style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                        decoration: _fieldDecoration(label: 'Unit'),
                        items: _dosageUnits
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => entry.dosageUnit = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _durationController,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [DigitsMaxInputFormatter(3)],
                        style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                        decoration: _fieldDecoration(label: 'Duration'),
                        onChanged: (v) {
                          entry.durationAmount = v;
                          _refreshAutoQuantity();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: ClinicalMockData.durationUnits.contains(entry.durationUnit)
                            ? entry.durationUnit
                            : ClinicalMockData.durationUnits.first,
                        isExpanded: true,
                        style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                        decoration: _fieldDecoration(label: 'Period'),
                        items: ClinicalMockData.durationUnits
                            .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            entry.durationUnit = v;
                            _refreshAutoQuantity();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _qtyController,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [DigitsMaxInputFormatter(4)],
                        style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                        decoration: _fieldDecoration(label: 'Qty'),
                        onChanged: (v) => entry.quantity = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Frequency',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _freqChip(
                      label: 'Morning',
                      short: 'M',
                      selected: entry.morning,
                      onSelected: (v) => entry.morning = v,
                    ),
                    const SizedBox(width: 8),
                    _freqChip(
                      label: 'Afternoon',
                      short: 'A',
                      selected: entry.afternoon,
                      onSelected: (v) => entry.afternoon = v,
                    ),
                    const SizedBox(width: 8),
                    _freqChip(
                      label: 'Night',
                      short: 'N',
                      selected: entry.night,
                      onSelected: (v) => entry.night = v,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilterChip(
                      label: Text('SOS', style: GoogleFonts.inter(fontSize: AppTypography.labelMedium)),
                      selected: entry.isSos,
                      selectedColor: AppColors.error.withValues(alpha: 0.12),
                      checkmarkColor: AppColors.error,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) => setState(() => entry.isSos = v),
                    ),
                    FilterChip(
                      label: Text('Substitute OK', style: GoogleFonts.inter(fontSize: AppTypography.labelMedium)),
                      selected: entry.substituteAllowed,
                      selectedColor: AppColors.doctorBlue.withValues(alpha: 0.12),
                      checkmarkColor: AppColors.doctorBlue,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) => setState(() => entry.substituteAllowed = v),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onToggleInstruction,
                    icon: Icon(
                      widget.showInstruction ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: Text(
                      widget.showInstruction ? 'Hide instructions' : 'Add instructions',
                      style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, fontWeight: FontWeight.w600),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.doctorBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                    ),
                  ),
                ),
                if (widget.showInstruction) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: entry.instructions.isEmpty ||
                                  !ClinicalMockData.instructionOptions.contains(entry.instructions)
                              ? ''
                              : entry.instructions,
                          isExpanded: true,
                          style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textPrimaryOf(context)),
                          decoration: _fieldDecoration(label: 'Timing'),
                          items: [
                            DropdownMenuItem<String>(
                              value: '',
                              child: Text('None', style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context))),
                            ),
                            ...ClinicalMockData.instructionOptions
                                .map((i) => DropdownMenuItem(value: i, child: Text(i))),
                          ],
                          onChanged: (v) {
                            setState(() => entry.instructions = v ?? '');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _specialInstructionsController,
                          style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                          decoration: _fieldDecoration(label: 'Special instructions'),
                          onChanged: (v) => entry.specialInstructions = v,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleConfirm,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      'Add to Rx',
                      style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.doctorBlue,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrollable medicine list — grows with content up to [maxHeight], then scrolls.
class RxMedicineList extends StatelessWidget {
  const RxMedicineList({
    super.key,
    required this.maxHeight,
    required this.children,
  });

  final double maxHeight;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const RxEmptyState();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.7)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            children: children,
          ),
        ),
      ),
    );
  }
}
