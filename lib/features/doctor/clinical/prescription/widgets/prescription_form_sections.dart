import '../../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../../core/session/doctor_session.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../profile/data/doctor_profile_store.dart';
import '../prescription_header_helper.dart';
import '../../data/clinical_mock_data.dart';
import '../../data/community_diagnosis_repository.dart';
import '../../data/community_investigations_repository.dart';
import '../../data/medical_tests_catalog.dart';
import '../../data/symptoms_database.dart';
import '../../models/clinical_models.dart';
import '../../widgets/clinical_widgets.dart';
import '../../widgets/clinical_input_formatters.dart';
import '../prescription_vital_validators.dart';
import 'multi_select_test_picker.dart';
import '../../../../../core/theme/app_typography.dart';

class PrescriptionHeaderSection extends StatefulWidget {
  const PrescriptionHeaderSection({
    super.key,
    required this.draft,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.collapsedSummary,
    this.dense = false,
  });

  final PrescriptionDraft draft;
  final bool collapsible;
  final bool initiallyExpanded;
  final String? collapsedSummary;
  final bool dense;

  @override
  State<PrescriptionHeaderSection> createState() => _PrescriptionHeaderSectionState();
}

class _PrescriptionHeaderSectionState extends State<PrescriptionHeaderSection> {
  String _timings = PrescriptionHeaderHelper.fallbackTimings;

  @override
  void initState() {
    super.initState();
    _loadTimings();
  }

  Future<void> _loadTimings() async {
    final t = await PrescriptionHeaderHelper.loadConsultationTimings(
      DoctorSession.loggedInDoctorId,
    );
    if (mounted) setState(() => _timings = t);
  }

  @override
  Widget build(BuildContext context) {
    final p = DoctorProfileStore.instance.profile;
    final address = PrescriptionHeaderHelper.clinicAddressLine(p);
    final qualifications = PrescriptionHeaderHelper.qualificationsLine(p);
    final doctorName = DoctorProfileStore.displayNameWithPrefix;
    final contact = p.mobile.trim().isEmpty ? 'Not set' : p.mobile.trim();
    final regNo = p.councilNumber.trim().isEmpty ? 'Not set' : p.councilNumber.trim();

    return ClinicalSectionCard(
      title: 'Doctor & clinic',
      collapsible: widget.collapsible,
      initiallyExpanded: widget.initiallyExpanded,
      collapsedSummary: widget.collapsedSummary ?? doctorName,
      dense: widget.dense,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            doctorName,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          if (qualifications.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              qualifications,
              style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
            ),
          ],
          const SizedBox(height: 10),
          if (p.specialization.trim().isNotEmpty)
            _DetailRow(label: 'Specialization', value: p.specialization.trim()),
          _DetailRow(
            label: 'Clinic',
            value: p.clinicName.trim().isEmpty ? 'Not set' : p.clinicName.trim(),
            muted: p.clinicName.trim().isEmpty,
          ),
          _DetailRow(
            label: 'Address',
            value: address.trim().isEmpty ? 'Not set' : address.trim(),
            muted: address.trim().isEmpty,
            maxLines: 3,
          ),
          _DetailRow(label: 'Contact', value: contact, muted: contact == 'Not set'),
          _DetailRow(label: 'Registration', value: regNo, muted: regNo == 'Not set'),
          _DetailRow(label: 'Timings', value: _timings, maxLines: 2),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          _DetailRow(label: 'Prescription ID', value: widget.draft.prescriptionId),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.muted = false,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final bool muted;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w500,
                color: muted ? AppColors.textSecondaryOf(context) : AppColors.textPrimaryOf(context),
                fontStyle: muted ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PrescriptionPatientSection extends StatelessWidget {
  const PrescriptionPatientSection({
    super.key,
    required this.draft,
    required this.weightController,
    required this.onChanged,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.collapsedSummary,
    this.dense = false,
  });

  final PrescriptionDraft draft;
  final TextEditingController weightController;
  final VoidCallback onChanged;
  final bool collapsible;
  final bool initiallyExpanded;
  final String? collapsedSummary;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final patient = draft.patient;
    final gender = patient.gender ?? '—';
    final date = DateFormat('dd MMM yyyy').format(draft.prescriptionDate);
    final patientId = draft.patientId.trim().isNotEmpty ? draft.patientId : 'Not linked';

    return ClinicalSectionCard(
      title: 'Patient',
      collapsible: collapsible,
      initiallyExpanded: initiallyExpanded,
      collapsedSummary: collapsedSummary ?? '${patient.patientName} · ${patient.age} yrs',
      dense: dense,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            patient.patientName,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$gender · ${patient.age} yrs · $date',
            style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'Patient ID',
            value: patientId,
            muted: patientId == 'Not linked',
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DecimalInputFormatter(maxIntegerDigits: 3, maxDecimalDigits: 1)],
            style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
            decoration: InputDecoration(
              labelText: 'Weight (kg)',
              isDense: true,
              filled: true,
              fillColor: AppColors.cardBgOf(context),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.8)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.8)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.doctorBlue, width: 1.2),
              ),
              labelStyle: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

class PrescriptionClinicalSection extends StatelessWidget {
  const PrescriptionClinicalSection({
    super.key,
    required this.draft,
    required this.chiefComplaintController,
    required this.primaryDxController,
    required this.secondaryDxController,
    required this.symptomsController,
    required this.durationController,
    required this.pastHistoryController,
    required this.allergiesController,
    required this.bpController,
    required this.tempController,
    required this.pulseController,
    required this.spo2Controller,
    required this.heightController,
    required this.respiratoryRateController,
    required this.generalExaminationController,
    required this.onChanged,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.collapsedSummary,
    this.dense = false,
  });

  final PrescriptionDraft draft;
  final TextEditingController chiefComplaintController;
  final TextEditingController primaryDxController;
  final TextEditingController secondaryDxController;
  final TextEditingController symptomsController;
  final TextEditingController durationController;
  final TextEditingController pastHistoryController;
  final TextEditingController allergiesController;
  final TextEditingController bpController;
  final TextEditingController tempController;
  final TextEditingController pulseController;
  final TextEditingController spo2Controller;
  final TextEditingController heightController;
  final TextEditingController respiratoryRateController;
  final TextEditingController generalExaminationController;
  final VoidCallback onChanged;
  final bool collapsible;
  final bool initiallyExpanded;
  final String? collapsedSummary;
  final bool dense;

  String get _summary {
    if (collapsedSummary != null && collapsedSummary!.trim().isNotEmpty) {
      return collapsedSummary!;
    }
    if (primaryDxController.text.trim().isNotEmpty) return primaryDxController.text.trim();
    if (chiefComplaintController.text.trim().isNotEmpty) {
      return chiefComplaintController.text.trim();
    }
    return 'Vitals, diagnosis & history';
  }

  @override
  Widget build(BuildContext context) {
    return ClinicalSectionCard(
      title: 'Clinical details',
      collapsible: collapsible,
      initiallyExpanded: initiallyExpanded,
      collapsedSummary: _summary,
      dense: dense,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vitals (optional)', style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _VitalField(
                  controller: bpController,
                  label: 'BP',
                  keyboardType: TextInputType.number,
                  formatters: const [BpInputFormatter()],
                  validator: PrescriptionVitalValidators.bloodPressure,
                  advisory: PrescriptionVitalValidators.bloodPressureAdvisory,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _VitalField(
                  controller: tempController,
                  label: 'Temp °F',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  formatters: const [DecimalInputFormatter(maxIntegerDigits: 3, maxDecimalDigits: 1)],
                  validator: PrescriptionVitalValidators.temperature,
                  advisory: PrescriptionVitalValidators.temperatureAdvisory,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _VitalField(
                  controller: pulseController,
                  label: 'Pulse',
                  keyboardType: TextInputType.number,
                  formatters: const [DigitsMaxInputFormatter(3)],
                  validator: PrescriptionVitalValidators.pulse,
                  advisory: PrescriptionVitalValidators.pulseAdvisory,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _VitalField(
                  controller: spo2Controller,
                  label: 'SpO2 %',
                  keyboardType: TextInputType.number,
                  formatters: const [DigitsMaxInputFormatter(3)],
                  validator: PrescriptionVitalValidators.spo2,
                  advisory: PrescriptionVitalValidators.spo2Advisory,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _VitalField(
                  controller: heightController,
                  label: 'Height cm',
                  keyboardType: TextInputType.number,
                  formatters: const [DigitsMaxInputFormatter(3)],
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _VitalField(
                  controller: respiratoryRateController,
                  label: 'Respiratory rate',
                  keyboardType: TextInputType.number,
                  formatters: const [DigitsMaxInputFormatter(3)],
                  validator: PrescriptionVitalValidators.respiratoryRate,
                  advisory: PrescriptionVitalValidators.respiratoryRateAdvisory,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: generalExaminationController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'General examination',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: chiefComplaintController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Chief complaint',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: draft.diagnosisType,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Diagnosis type'),
            items: ClinicalMockData.diagnosisTypes
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                draft.diagnosisType = v;
                onChanged();
              }
            },
          ),
          const SizedBox(height: 12),
          _DiagnosisSearchField(
            label: 'Primary diagnosis (ICD-10)',
            controller: primaryDxController,
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          _DiagnosisSearchField(
            label: 'Secondary diagnosis',
            controller: secondaryDxController,
            onChanged: onChanged,
            optional: true,
          ),
          const SizedBox(height: 12),
          _SymptomsSearchField(
            controller: symptomsController,
            onSelected: (_) => onChanged(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: durationController,
            decoration: const InputDecoration(labelText: 'Duration'),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: pastHistoryController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Past medical history', alignLabelWithHint: true),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: allergiesController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Known allergies',
              alignLabelWithHint: true,
              filled: true,
              fillColor: AppColors.isDark(context) ? const Color(0xFF2D1515) : const Color(0xFFFEF2F2),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.error.withValues(alpha: 0.35)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.error.withValues(alpha: 0.6)),
              ),
              prefixIcon: Icon(Icons.warning_amber_rounded, color: AppColors.error.withValues(alpha: 0.8)),
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }

}

class _VitalField extends StatefulWidget {
  const _VitalField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.formatters,
    this.keyboardType,
    this.validator,
    this.advisory,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;
  final List<TextInputFormatter>? formatters;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final VitalAdvisory Function(String?)? advisory;

  @override
  State<_VitalField> createState() => _VitalFieldState();
}

class _VitalFieldState extends State<_VitalField> {
  VitalAdvisory _advisory = const VitalAdvisory.none();

  static const _hypothermiaColor = Color(0xFF2563EB);
  static const _normalColor = Color(0xFF16A34A);
  static const _cautionColor = Color(0xFFCA8A04);
  static const _warningColor = Color(0xFFEA580C);

  @override
  void initState() {
    super.initState();
    _refreshAdvisory(widget.controller.text);
  }

  void _refreshAdvisory(String value) {
    final next = widget.advisory?.call(value) ?? const VitalAdvisory.none();
    if (next.level != _advisory.level || next.message != _advisory.message) {
      setState(() => _advisory = next);
    }
  }

  Color? _advisoryColor() {
    return switch (_advisory.level) {
      VitalAdvisoryLevel.hypothermia => _hypothermiaColor,
      VitalAdvisoryLevel.normal => _normalColor,
      VitalAdvisoryLevel.caution => _cautionColor,
      VitalAdvisoryLevel.warning => _warningColor,
      VitalAdvisoryLevel.critical => AppColors.error,
      VitalAdvisoryLevel.none => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final advisoryColor = _advisoryColor();

    return TextFormField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.formatters,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: _advisory.hasMessage ? _advisory.message : null,
        helperMaxLines: 2,
        helperStyle: advisoryColor != null
            ? GoogleFonts.inter(fontSize: 10, color: advisoryColor, height: 1.2)
            : null,
        enabledBorder: advisoryColor != null
            ? OutlineInputBorder(
                borderSide: BorderSide(color: advisoryColor.withValues(alpha: 0.55)),
              )
            : null,
        focusedBorder: advisoryColor != null
            ? OutlineInputBorder(
                borderSide: BorderSide(color: advisoryColor, width: 1.5),
              )
            : null,
      ),
      validator: widget.validator,
      onChanged: (value) {
        _refreshAdvisory(value);
        widget.onChanged();
      },
    );
  }
}

class _SymptomsSearchField extends StatelessWidget {
  const _SymptomsSearchField({
    required this.controller,
    required this.onSelected,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SymptomsDatabase.instance,
      builder: (context, _) {
        return SearchSuggestionsField(
          key: ValueKey(SymptomsDatabase.instance.isLoaded),
          label: 'Symptoms',
          controller: controller,
          suggestionFetcher: SymptomsDatabase.instance.search,
          optional: true,
          maxSuggestionsHeight: 280,
          onSelected: onSelected,
        );
      },
    );
  }
}

class _DiagnosisSearchField extends StatelessWidget {
  const _DiagnosisSearchField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.optional = false,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool optional;

  Future<void> _addCustomDiagnosis(BuildContext context) async {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    final doctorId = DoctorSession.loggedInDoctorId.trim();
    if (doctorId.isEmpty) {
      AppToast.info(context, 'Doctor session not found. Please login again.');
      return;
    }

    try {
      await CommunityDiagnosisRepository.instance.addDiagnosis(
        text: text,
        doctorId: doctorId,
      );
    } catch (e) {
      if (!context.mounted) return;
      AppToast.info(context, 'Could not save diagnosis: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchSuggestionsField(
          label: label,
          controller: controller,
          suggestionFetcher: CommunityDiagnosisRepository.instance.searchMerged,
          onSelected: (_) => onChanged(),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final raw = value.text.trim();
            if (raw.isEmpty) return const SizedBox.shrink();
            if (CommunityDiagnosisRepository.instance.isKnownDisplay(raw)) {
              return const SizedBox.shrink();
            }

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
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
                      optional
                          ? 'Custom diagnosis — save to shared database (optional)'
                          : 'Not in ICD-10 list — save to shared database',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _addCustomDiagnosis(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.doctorBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '+ Save diagnosis',
                      style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class PrescriptionInvestigationsSection extends StatelessWidget {
  const PrescriptionInvestigationsSection({
    super.key,
    required this.draft,
    required this.onChanged,
    this.customAuthorId,
    this.allowCustomTests = true,
    this.allowClinicalNotes = true,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.dense = false,
  });

  final PrescriptionDraft draft;
  final VoidCallback onChanged;
  final String? customAuthorId;
  final bool allowCustomTests;
  final bool allowClinicalNotes;
  final bool collapsible;
  final bool initiallyExpanded;
  final bool dense;

  String get _authorId {
    if (customAuthorId != null && customAuthorId!.isNotEmpty) return customAuthorId!;
    return DoctorSession.loggedInDoctorId;
  }

  int get _totalCount {
    return draft.investigations.length + draft.bodyParts.length;
  }

  List<InvestigationEntry> get _labEntries =>
      draft.investigations.where((e) => e.type == InvestigationType.lab).toList();

  List<InvestigationEntry> get _labCustom => draft.investigations
      .where((e) => e.type == InvestigationType.custom && e.group == 'lab')
      .toList();

  List<InvestigationEntry> get _radiologyEntries =>
      draft.investigations.where((e) => e.type == InvestigationType.radiology).toList();

  List<InvestigationEntry> get _radiologyCustom => draft.investigations
      .where((e) => e.type == InvestigationType.custom && e.group == 'radiology')
      .toList();

  Future<void> _pickLabTests(BuildContext context) async {
    final selectedIds = _labEntries
        .where((e) => e.catalogId != null)
        .map((e) => e.catalogId!)
        .toSet();
    final customNames = allowCustomTests ? _labCustom.map((e) => e.name).toList() : const <String>[];

    final result = await MultiSelectTestPicker.show(
      context,
      title: 'Select Lab Tests',
      catalog: CommunityInvestigationsRepository.instance.mergedLabCatalog(),
      initiallySelectedIds: selectedIds,
      initiallyCustomNames: customNames,
      customAddLabel: '+ Add Lab Test',
      allowCustomAdd: allowCustomTests,
      onPersistCustom: allowCustomTests
          ? (name) async {
              final test = await CommunityInvestigationsRepository.instance.addLabTest(
                name: name,
                group: 'Custom',
                doctorId: _authorId,
              );
              return test?.id;
            }
          : null,
    );
    if (result == null) return;
    _applyLabSelection(result);
    onChanged();
  }

  void _applyLabSelection(TestPickerResult result) {
    final existingByCatalog = <String, InvestigationEntry>{};
    final existingByCustom = <String, InvestigationEntry>{};
    for (final e in draft.investigations) {
      if (e.type == InvestigationType.lab && e.catalogId != null) {
        existingByCatalog[e.catalogId!] = e;
      } else if (e.type == InvestigationType.custom && e.group == 'lab') {
        existingByCustom[e.name] = e;
      }
    }

    draft.investigations.removeWhere((e) =>
        e.type == InvestigationType.lab ||
        (e.type == InvestigationType.custom && e.group == 'lab'));

    for (final id in result.selectedIds) {
      final item = CommunityInvestigationsRepository.instance.resolveLabCatalogItem(id);
      if (item == null) continue;
      final prev = existingByCatalog[id];
      draft.investigations.add(InvestigationEntry(
        type: InvestigationType.lab,
        name: item.name,
        group: item.group,
        catalogId: item.id,
        notes: prev?.notes ?? '',
      ));
    }
    for (final c in result.customNames) {
      if (!allowCustomTests) continue;
      final prev = existingByCustom[c];
      draft.investigations.add(InvestigationEntry(
        type: InvestigationType.custom,
        name: c,
        group: 'lab',
        notes: prev?.notes ?? '',
      ));
    }
  }

  Future<void> _pickRadiology(BuildContext context) async {
    final selectedIds = _radiologyEntries
        .where((e) => e.catalogId != null)
        .map((e) => e.catalogId!)
        .toSet();
    final customNames = allowCustomTests ? _radiologyCustom.map((e) => e.name).toList() : const <String>[];

    final result = await MultiSelectTestPicker.show(
      context,
      title: 'Select Radiology Tests',
      catalog: CommunityInvestigationsRepository.instance.mergedRadiologyCatalog(),
      initiallySelectedIds: selectedIds,
      initiallyCustomNames: customNames,
      customAddLabel: '+ Add Radiology Test',
      allowCustomAdd: allowCustomTests,
      onPersistCustom: allowCustomTests
          ? (name) async {
              final test = await CommunityInvestigationsRepository.instance.addRadiologyTest(
                name: name,
                group: 'Custom',
                doctorId: _authorId,
              );
              return test?.id;
            }
          : null,
    );
    if (result == null) return;
    _applyRadiologySelection(result);
    onChanged();
  }

  void _applyRadiologySelection(TestPickerResult result) {
    final existingByCatalog = <String, InvestigationEntry>{};
    final existingByCustom = <String, InvestigationEntry>{};
    for (final e in draft.investigations) {
      if (e.type == InvestigationType.radiology && e.catalogId != null) {
        existingByCatalog[e.catalogId!] = e;
      } else if (e.type == InvestigationType.custom && e.group == 'radiology') {
        existingByCustom[e.name] = e;
      }
    }

    draft.investigations.removeWhere((e) =>
        e.type == InvestigationType.radiology ||
        (e.type == InvestigationType.custom && e.group == 'radiology'));

    for (final id in result.selectedIds) {
      final item = CommunityInvestigationsRepository.instance.resolveRadiologyCatalogItem(id);
      if (item == null) continue;
      final prev = existingByCatalog[id];
      draft.investigations.add(InvestigationEntry(
        type: InvestigationType.radiology,
        name: item.name,
        group: item.group,
        catalogId: item.id,
        notes: prev?.notes ?? '',
      ));
    }
    for (final c in result.customNames) {
      if (!allowCustomTests) continue;
      final prev = existingByCustom[c];
      draft.investigations.add(InvestigationEntry(
        type: InvestigationType.custom,
        name: c,
        group: 'radiology',
        notes: prev?.notes ?? '',
      ));
    }
  }

  Future<void> _pickBodyParts(BuildContext context) async {
    final result = await MultiSelectStringPicker.show(
      context,
      title: 'Select Body Part / Region',
      options: CommunityInvestigationsRepository.instance.mergedBodyParts(),
      initiallySelected: draft.bodyParts,
      allowCustomAdd: allowCustomTests,
      onPersistCustom: allowCustomTests
          ? (name) async {
              final part = await CommunityInvestigationsRepository.instance.addBodyPart(
                name: name,
                doctorId: _authorId,
              );
              return part?.name;
            }
          : null,
    );
    if (result == null) return;
    draft.bodyParts
      ..clear()
      ..addAll(result);
    onChanged();
  }

  bool _isTemplateFullyActive(String templateName) {
    final ids = MedicalTestsCatalog.templates[templateName];
    if (ids == null || ids.isEmpty) return false;
    final activeCatalogIds = draft.investigations
        .where((e) => e.catalogId != null)
        .map((e) => e.catalogId!)
        .toSet();
    return ids.every(activeCatalogIds.contains);
  }

  void _applyTemplate(String templateName) {
    final ids = MedicalTestsCatalog.templates[templateName] ?? [];
    if (ids.isEmpty) return;

    if (_isTemplateFullyActive(templateName)) {
      final removeIds = ids.toSet();
      draft.investigations.removeWhere(
        (e) => e.catalogId != null && removeIds.contains(e.catalogId),
      );
      onChanged();
      return;
    }

    for (final id in ids) {
      if (draft.investigations.any((e) => e.catalogId == id)) continue;
      final lab = CommunityInvestigationsRepository.instance.resolveLabCatalogItem(id);
      if (lab != null) {
        draft.investigations.add(InvestigationEntry(
          type: InvestigationType.lab,
          name: lab.name,
          group: lab.group,
          catalogId: lab.id,
        ));
        continue;
      }
      final rad = CommunityInvestigationsRepository.instance.resolveRadiologyCatalogItem(id);
      if (rad != null) {
        draft.investigations.add(InvestigationEntry(
          type: InvestigationType.radiology,
          name: rad.name,
          group: rad.group,
          catalogId: rad.id,
        ));
      }
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final visibleLabEntries = [..._labEntries, if (allowCustomTests) ..._labCustom];
    final visibleRadiologyEntries = [..._radiologyEntries, if (allowCustomTests) ..._radiologyCustom];

    return ClinicalSectionCard(
      title: 'Tests',
      collapsible: collapsible,
      initiallyExpanded: initiallyExpanded,
      collapsedSummary: _totalCount > 0 ? '$_totalCount selected' : 'Lab, radiology & body parts',
      dense: dense,
      trailing: _totalCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.doctorBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_totalCount',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: AppColors.surfaceOf(context),
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Templates row
          Text(
            'Quick Templates',
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              color: AppColors.textSecondaryOf(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: MedicalTestsCatalog.templates.keys.map((t) {
              final active = _isTemplateFullyActive(t);
              return ActionChip(
                avatar: Icon(
                  Icons.flash_on,
                  size: 14,
                  color: active ? AppColors.surfaceOf(context) : AppColors.doctorBlue,
                ),
                label: Text(
                  t,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelSmall,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? AppColors.surfaceOf(context) : AppColors.textPrimaryOf(context),
                  ),
                ),
                backgroundColor: active ? AppColors.doctorBlue : null,
                side: active
                    ? BorderSide.none
                    : BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.8)),
                onPressed: () => _applyTemplate(t),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // LAB TESTS
          _PickerField(
            label: 'Lab Tests',
            icon: Icons.biotech,
            count: visibleLabEntries.length,
            onTap: () => _pickLabTests(context),
          ),
          if (visibleLabEntries.isNotEmpty)
            _SelectedTestList(
              entries: visibleLabEntries,
              allowClinicalNotes: allowClinicalNotes,
              onRemove: (entry) {
                draft.investigations.removeWhere((e) => e.id == entry.id);
                onChanged();
              },
              onNotesChanged: (entry, value) {
                entry.notes = value;
                onChanged();
              },
            ),
          const SizedBox(height: 12),

          // RADIOLOGY
          _PickerField(
            label: 'Radiology',
            icon: Icons.medical_services_outlined,
            count: visibleRadiologyEntries.length,
            onTap: () => _pickRadiology(context),
          ),
          if (visibleRadiologyEntries.isNotEmpty)
            _SelectedTestList(
              entries: visibleRadiologyEntries,
              allowClinicalNotes: allowClinicalNotes,
              onRemove: (entry) {
                draft.investigations.removeWhere((e) => e.id == entry.id);
                onChanged();
              },
              onNotesChanged: (entry, value) {
                entry.notes = value;
                onChanged();
              },
            ),
          const SizedBox(height: 12),

          // BODY PART / REGION
          _PickerField(
            label: 'Body Part / Region',
            icon: Icons.accessibility_new,
            count: draft.bodyParts.length,
            onTap: () => _pickBodyParts(context),
          ),
          if (draft.bodyParts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: draft.bodyParts.map((bp) {
                return InputChip(
                  label: Text(bp, style: GoogleFonts.inter(fontSize: AppTypography.labelMedium)),
                  backgroundColor: AppColors.doctorBlue.withValues(alpha: 0.08),
                  onDeleted: () {
                    draft.bodyParts.remove(bp);
                    draft.bodyPartNotes.remove(bp);
                    onChanged();
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.icon,
    required this.count,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderOf(context)),
            borderRadius: BorderRadius.circular(8),
            color: AppColors.surfaceOf(context),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.doctorBlue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: count > 0 ? 12 : 13,
                        color: count > 0 ? AppColors.textSecondaryOf(context) : AppColors.textPrimaryOf(context),
                        fontWeight: count > 0 ? FontWeight.w500 : FontWeight.w600,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$count selected',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodySmall,
                          color: AppColors.textPrimaryOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: AppColors.doctorBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      fontWeight: FontWeight.w700,
                      color: AppColors.surfaceOf(context),
                    ),
                  ),
                ),
              Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedTestList extends StatelessWidget {
  const _SelectedTestList({
    required this.entries,
    required this.onRemove,
    required this.onNotesChanged,
    this.allowClinicalNotes = true,
  });

  final List<InvestigationEntry> entries;
  final void Function(InvestigationEntry entry) onRemove;
  final void Function(InvestigationEntry entry, String value) onNotesChanged;
  final bool allowClinicalNotes;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<InvestigationEntry>>{};
    for (final e in entries) {
      final key = e.type == InvestigationType.custom ? 'Custom' : (e.group.isEmpty ? 'Other' : e.group);
      groups.putIfAbsent(key, () => []).add(e);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: groups.entries.map((groupEntry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    groupEntry.key.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.doctorBlue,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ...groupEntry.value.map((entry) => _SelectedTestTile(
                      entry: entry,
                      allowClinicalNotes: allowClinicalNotes,
                      onRemove: () => onRemove(entry),
                      onNotesChanged: (v) => onNotesChanged(entry, v),
                    )),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SelectedTestTile extends StatefulWidget {
  const _SelectedTestTile({
    required this.entry,
    required this.onRemove,
    required this.onNotesChanged,
    this.allowClinicalNotes = true,
  });

  final InvestigationEntry entry;
  final VoidCallback onRemove;
  final ValueChanged<String> onNotesChanged;
  final bool allowClinicalNotes;

  @override
  State<_SelectedTestTile> createState() => _SelectedTestTileState();
}

class _SelectedTestTileState extends State<_SelectedTestTile> {
  bool _notesExpanded = false;
  late final TextEditingController _notesController =
      TextEditingController(text: widget.entry.notes);

  @override
  void initState() {
    super.initState();
    _notesExpanded = widget.entry.notes.isNotEmpty;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.doctorBlue.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.doctorBlue.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.entry.name,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ),
                if (widget.allowClinicalNotes)
                  IconButton(
                    onPressed: () => setState(() => _notesExpanded = !_notesExpanded),
                    icon: Icon(
                      _notesExpanded ? Icons.note : Icons.note_add_outlined,
                      size: 18,
                      color: AppColors.doctorBlue,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Add notes / reason',
                  ),
                if (widget.allowClinicalNotes)
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFFDC2626)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove',
                  )
                else
                  FilledButton.icon(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close, size: 14, color: Colors.white),
                    label: Text(
                      'Remove',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.surfaceOf(context),
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.allowClinicalNotes && _notesExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes / reason',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                style: GoogleFonts.inter(fontSize: AppTypography.labelMedium),
                onChanged: widget.onNotesChanged,
              ),
            ),
        ],
      ),
    );
  }
}

class PrescriptionAdviceSection extends StatelessWidget {
  const PrescriptionAdviceSection({
    super.key,
    required this.dietController,
    required this.activityController,
    required this.lifestyleController,
    required this.generalAdviceController,
    required this.onChanged,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.dense = false,
    this.includeFollowUp = false,
    this.draft,
    this.followUpNoteController,
    this.onPickNextVisit,
  });

  final TextEditingController dietController;
  final TextEditingController activityController;
  final TextEditingController lifestyleController;
  final TextEditingController generalAdviceController;
  final VoidCallback onChanged;
  final bool collapsible;
  final bool initiallyExpanded;
  final bool dense;
  final bool includeFollowUp;
  final PrescriptionDraft? draft;
  final TextEditingController? followUpNoteController;
  final VoidCallback? onPickNextVisit;

  @override
  Widget build(BuildContext context) {
    return ClinicalSectionCard(
      title: includeFollowUp ? 'Advice & follow-up' : 'Advice',
      collapsible: collapsible,
      initiallyExpanded: initiallyExpanded,
      collapsedSummary: 'Diet, lifestyle & follow-up notes',
      dense: dense,
      child: Column(
        children: [
          TextFormField(
            controller: dietController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Diet advice', alignLabelWithHint: true, isDense: true),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: activityController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Rest & activity restrictions', alignLabelWithHint: true, isDense: true),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: lifestyleController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Lifestyle changes', alignLabelWithHint: true, isDense: true),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: generalAdviceController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'General advice', alignLabelWithHint: true, isDense: true),
            onChanged: (_) => onChanged(),
          ),
          if (includeFollowUp && draft != null && followUpNoteController != null && onPickNextVisit != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            PrescriptionFollowUpFields(
              draft: draft!,
              followUpNoteController: followUpNoteController!,
              onPickNextVisit: onPickNextVisit!,
              onChanged: onChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class PrescriptionFollowUpFields extends StatelessWidget {
  const PrescriptionFollowUpFields({
    super.key,
    required this.draft,
    required this.followUpNoteController,
    required this.onPickNextVisit,
    required this.onChanged,
  });

  final PrescriptionDraft draft;
  final TextEditingController followUpNoteController;
  final VoidCallback onPickNextVisit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final next = draft.nextVisit;
    final nextLabel = next == null ? 'Not set' : DateFormat('dd MMM yyyy').format(next);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onPickNextVisit,
          icon: const Icon(Icons.event_outlined, size: 16),
          label: Text('Next visit: $nextLabel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.doctorBlue,
            side: const BorderSide(color: AppColors.doctorBlue),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: followUpNoteController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Condition-based note',
            alignLabelWithHint: true,
            isDense: true,
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

class PrescriptionFollowUpSection extends StatelessWidget {
  const PrescriptionFollowUpSection({
    super.key,
    required this.draft,
    required this.followUpNoteController,
    required this.onPickNextVisit,
    required this.onChanged,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.dense = false,
  });

  final PrescriptionDraft draft;
  final TextEditingController followUpNoteController;
  final VoidCallback onPickNextVisit;
  final VoidCallback onChanged;
  final bool collapsible;
  final bool initiallyExpanded;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ClinicalSectionCard(
      title: '7. Follow-up',
      collapsible: collapsible,
      initiallyExpanded: initiallyExpanded,
      collapsedSummary: draft.nextVisit == null ? 'Schedule next visit' : DateFormat('dd MMM yyyy').format(draft.nextVisit!),
      dense: dense,
      child: PrescriptionFollowUpFields(
        draft: draft,
        followUpNoteController: followUpNoteController,
        onPickNextVisit: onPickNextVisit,
        onChanged: onChanged,
      ),
    );
  }
}

class PrescriptionReferralsSection extends StatelessWidget {
  const PrescriptionReferralsSection({
    super.key,
    required this.draft,
    required this.onOpenReferDialog,
    required this.onRemoveReferral,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.dense = false,
  });

  final PrescriptionDraft draft;
  final VoidCallback onOpenReferDialog;
  final ValueChanged<int> onRemoveReferral;
  final bool collapsible;
  final bool initiallyExpanded;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final count = draft.referrals.length;
    final summary = count == 0 ? 'No referrals added' : '$count specialist(s)';

    return ClinicalSectionCard(
      title: 'Refer patient',
      collapsible: collapsible,
      initiallyExpanded: initiallyExpanded,
      collapsedSummary: summary,
      dense: dense,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: onOpenReferDialog,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Select specialist to refer'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.doctorBlue,
              side: const BorderSide(color: AppColors.doctorBlue),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          if (draft.referrals.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < draft.referrals.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.doctorBlue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.doctorBlue.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            draft.referrals[i].displayTitle,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (draft.referrals[i].reason.isNotEmpty)
                            Text(
                              draft.referrals[i].reason,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.labelSmall,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (draft.referrals[i].sent)
                      Text(
                        'Sent',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF16A34A),
                        ),
                      )
                    else
                      IconButton(
                        onPressed: () => onRemoveReferral(i),
                        icon: const Icon(Icons.close, size: 18, color: Color(0xFFDC2626)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class PrescriptionPractoActions extends StatelessWidget {
  const PrescriptionPractoActions({
    super.key,
    required this.onPreview,
    required this.onSave,
    required this.onShare,
    required this.onHistory,
    this.saveLabel = 'Save',
  });

  final VoidCallback onPreview;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onHistory;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    final compactText = GoogleFonts.inter(fontSize: AppTypography.labelSmall, fontWeight: FontWeight.w600);
    final filledStyle = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      minimumSize: const Size(0, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: compactText,
    );
    final outlinedStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      minimumSize: const Size(0, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: compactText,
      foregroundColor: AppColors.doctorBlue,
      side: const BorderSide(color: AppColors.doctorBlue),
    );
    final saveStyle = filledStyle.copyWith(
      backgroundColor: WidgetStateProperty.all(const Color(0xFF16A34A)),
      foregroundColor: WidgetStateProperty.all(AppColors.white),
    );

    final buttons = Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: onPreview,
            style: filledStyle,
            child: const Text('Preview', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onShare,
            style: outlinedStyle,
            icon: const Icon(Icons.send_outlined, size: 16),
            label: const Text('Send', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton(
            onPressed: onHistory,
            style: outlinedStyle,
            child: const Text('History', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ElevatedButton(
            onPressed: onSave,
            style: saveStyle,
            child: Text(saveLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: buttons,
    );
  }
}
