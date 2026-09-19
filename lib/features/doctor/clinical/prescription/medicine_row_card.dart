import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/labeled_add_button.dart';
import '../../../../widgets/labeled_remove_button.dart';
import '../data/clinical_mock_data.dart';
import '../data/community_medicine_repository.dart';
import '../data/dosage_units.dart';
import '../models/clinical_models.dart';
import '../widgets/clinical_input_formatters.dart';
import '../widgets/clinical_widgets.dart';
import 'add_community_medicine_dialog.dart';
import '../../../../core/theme/app_typography.dart';

List<String> _mergedDosageUnits(String current) => dosageUnitsIncluding(current);

List<String> _mergedMedicineForms(String current) {
  final forms = <String>{...ClinicalMockData.medicineForms, ...kCommunityMedicineForms};
  if (current.isNotEmpty) forms.add(current);
  return forms.toList();
}

class MedicineRowCard extends StatelessWidget {
  const MedicineRowCard({
    super.key,
    required this.entry,
    required this.index,
    required this.nameController,
    required this.onAdd,
    required this.onDelete,
    required this.onChanged,
    this.canDelete = true,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  final MedicineEntry entry;
  final int index;
  final TextEditingController nameController;
  final VoidCallback onAdd;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final bool canDelete;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  void _applyMedicineSelection(MedicineEntry entry, MedicineSearchSuggestion item) {
    entry.name = item.name;
    if (item.dosageUnit != null && item.dosageUnit!.isNotEmpty) {
      entry.dosageUnit = item.dosageUnit!;
    }
    if (item.form != null && item.form!.isNotEmpty) {
      entry.form = item.form!;
    }
  }

  void _applyCommunityMedicine(MedicineEntry entry, CommunityMedicine medicine) {
    entry.name = medicine.name;
    entry.dosageUnit = medicine.dosageUnit;
    entry.form = medicine.form;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.doctorBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.doctorBlue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '℞ Medicine ${index + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w700,
                    color: AppColors.doctorBlue,
                  ),
                ),
              ),
              if (entry.isSos) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'SOS',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFEA580C),
                    ),
                  ),
                ),
              ],
              if (canMoveUp)
                IconButton(
                  onPressed: onMoveUp,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              if (canMoveDown)
                IconButton(
                  onPressed: onMoveDown,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              LabeledAddButton(
                label: 'Add Medicine',
                onPressed: onAdd,
              ),
              LabeledRemoveButton(
                label: 'Remove',
                onPressed: canDelete ? onDelete : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SearchSuggestionsField(
            label: 'Medicine name',
            controller: nameController,
            itemSuggestionFetcher: (q) {
              if (q.trim().isEmpty) return const [];
              return CommunityMedicineRepository.instance.searchMerged(q);
            },
            onItemSelected: (item) {
              _applyMedicineSelection(entry, item);
              onChanged();
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: nameController,
            builder: (context, value, _) {
              final raw = value.text.trim();
              if (raw.isEmpty) return const SizedBox.shrink();

              if (CommunityMedicineRepository.instance.isKnownName(raw)) {
                return const SizedBox.shrink();
              }

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.cardBgOf(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Medicine not found in database',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    LabeledAddButton(
                      label: '+ Add Medicine',
                      onPressed: () async {
                        final medicine = await AddCommunityMedicineDialog.show(context, raw);
                        if (!context.mounted || medicine == null) return;
                        await CommunityMedicineRepository.instance.fetchAll();
                        if (!context.mounted) return;
                        nameController.text = medicine.name;
                        _applyCommunityMedicine(entry, medicine);
                        onChanged();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: entry.dosageAmount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [
                    DecimalInputFormatter(maxIntegerDigits: 4, maxDecimalDigits: 2),
                  ],
                  decoration: const InputDecoration(labelText: 'Dosage / Strength'),
                  onChanged: (v) {
                    entry.dosageAmount = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: entry.dosageUnit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: _mergedDosageUnits(entry.dosageUnit)
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      entry.dosageUnit = v;
                      onChanged();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: entry.form,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Form'),
                  items: _mergedMedicineForms(entry.form)
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      entry.form = v;
                      onChanged();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Frequency (M · A · N)', style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: 6),
          Row(
            children: [
              _MealToggle(
                label: 'Morning',
                selected: entry.morning,
                onChanged: (v) {
                  entry.morning = v;
                  entry.useCustomFrequency = false;
                  entry.recalculateQuantity();
                  onChanged();
                },
              ),
              const SizedBox(width: 8),
              _MealToggle(
                label: 'Afternoon',
                selected: entry.afternoon,
                onChanged: (v) {
                  entry.afternoon = v;
                  entry.useCustomFrequency = false;
                  entry.recalculateQuantity();
                  onChanged();
                },
              ),
              const SizedBox(width: 8),
              _MealToggle(
                label: 'Night',
                selected: entry.night,
                onChanged: (v) {
                  entry.night = v;
                  entry.useCustomFrequency = false;
                  entry.recalculateQuantity();
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: entry.customFrequency,
            decoration: const InputDecoration(
              labelText: 'Custom frequency (optional)',
            ),
            onChanged: (v) {
              entry.customFrequency = v;
              entry.useCustomFrequency = v.trim().isNotEmpty;
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: entry.instructions.isEmpty ||
                          !ClinicalMockData.instructionOptions.contains(entry.instructions)
                      ? ''
                      : entry.instructions,
                  decoration: const InputDecoration(labelText: 'Timing'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('None')),
                    ...ClinicalMockData.instructionOptions
                        .map((i) => DropdownMenuItem(value: i, child: Text(i))),
                  ],
                  onChanged: (v) {
                    entry.instructions = v ?? '';
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: entry.durationAmount,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [DigitsMaxInputFormatter(3)],
                  decoration: const InputDecoration(labelText: 'Duration'),
                  onChanged: (v) {
                    entry.durationAmount = v;
                    entry.recalculateQuantity();
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: entry.durationUnit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: ' '),
                  items: ClinicalMockData.durationUnits
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      entry.durationUnit = v;
                      entry.recalculateQuantity();
                      onChanged();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('qty-${entry.id}-${entry.quantity}'),
                  initialValue: entry.quantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [DigitsMaxInputFormatter(4)],
                  decoration: const InputDecoration(labelText: 'Quantity (auto)'),
                  onChanged: (v) {
                    entry.quantity = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: entry.specialInstructions,
                  decoration: const InputDecoration(labelText: 'Special instructions'),
                  onChanged: (v) {
                    entry.specialInstructions = v;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('SOS'),
                selected: entry.isSos,
                onSelected: (v) {
                  entry.isSos = v;
                  onChanged();
                },
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FilterChip(
                  label: const Text('Substitute allowed'),
                  selected: entry.substituteAllowed,
                  onSelected: (v) {
                    entry.substituteAllowed = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  entry.frequencyLabel,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w600,
                    color: AppColors.doctorBlue,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealToggle extends StatelessWidget {
  const _MealToggle({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.doctorBlue : AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => onChanged(!selected),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.doctorBlue : AppColors.borderOf(context),
              ),
            ),
            child: Text(
              label[0],
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.surfaceOf(context) : AppColors.textPrimaryOf(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
