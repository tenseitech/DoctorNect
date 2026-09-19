import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/multi_tag_input_field.dart';
import '../../../../core/theme/app_typography.dart';

const kCommonSymptoms = [
  'Fever',
  'Cough',
  'Headache',
  'Fatigue',
  'Nausea',
  'Pain',
  'Vomiting',
  'Dizziness',
  'Cold',
  'Breathlessness',
];

/// Read-only symptom chips (e.g. appointment list cards).
class SymptomChipsPreview extends StatelessWidget {
  const SymptomChipsPreview({
    super.key,
    required this.symptoms,
    this.maxVisible = 3,
  });

  final List<String> symptoms;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (symptoms.isEmpty) return const SizedBox.shrink();

    final visible = symptoms.take(maxVisible).toList();
    final extra = symptoms.length - visible.length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in visible)
          Chip(
            label: Text(s, style: GoogleFonts.inter(fontSize: AppTypography.labelSmall)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: AppColors.doctorBlue.withValues(alpha: 0.1),
            side: BorderSide(color: AppColors.doctorBlue.withValues(alpha: 0.25)),
            labelStyle: GoogleFonts.inter(
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w500,
              color: AppColors.doctorBlue,
            ),
          ),
        if (extra > 0)
          Chip(
            label: Text('+$extra', style: GoogleFonts.inter(fontSize: AppTypography.labelSmall)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: AppColors.textSecondaryOf(context).withValues(alpha: 0.1),
          ),
      ],
    );
  }
}

/// Editable symptoms list for appointment detail — persists via [SharedAppointmentsStore].
class AppointmentSymptomsSection extends StatefulWidget {
  const AppointmentSymptomsSection({
    super.key,
    required this.recordId,
    required this.initialSymptoms,
  });

  final String recordId;
  final List<String> initialSymptoms;

  @override
  State<AppointmentSymptomsSection> createState() => _AppointmentSymptomsSectionState();
}

class _AppointmentSymptomsSectionState extends State<AppointmentSymptomsSection> {
  late List<String> _symptoms;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _symptoms = List<String>.from(widget.initialSymptoms);
  }

  @override
  void didUpdateWidget(covariant AppointmentSymptomsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSymptoms != widget.initialSymptoms) {
      _symptoms = List<String>.from(widget.initialSymptoms);
    }
  }

  void _add(String value) {
    final key = value.trim().toLowerCase();
    if (key.isEmpty || _symptoms.any((s) => s.toLowerCase() == key)) return;
    setState(() => _symptoms.add(value.trim()));
  }

  void _remove(String value) {
    setState(() {
      _symptoms.removeWhere((s) => s.toLowerCase() == value.toLowerCase());
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await SharedAppointmentsStore.instance.saveSymptoms(
      recordId: widget.recordId,
      symptoms: _symptoms,
    );
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Symptoms',
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          MultiTagInputField(
            tags: _symptoms,
            onAdd: _add,
            onRemove: _remove,
            hintText: 'Enter symptom',
            quickAddLabels: kCommonSymptoms,
            quickAddTitle: 'Common symptoms',
            addButtonLabel: 'Add Symptom',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.doctorBlue,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: _saving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.surfaceOf(context),
                      ),
                    )
                  : Text(
                      'Save Symptoms',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
