import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/labeled_add_button.dart';
import '../data/clinical_mock_data.dart';
import '../models/clinical_models.dart';
import '../widgets/clinical_widgets.dart';

class ClinicalNotesScreen extends StatefulWidget {
  const ClinicalNotesScreen({super.key, required this.patient});

  final PatientClinicalContext patient;

  @override
  State<ClinicalNotesScreen> createState() => _ClinicalNotesScreenState();
}

class _ClinicalNotesScreenState extends State<ClinicalNotesScreen> {
  final _chiefComplaint = TextEditingController();
  final _hpi = TextEditingController();
  final _pmh = TextEditingController();
  final _familyHistory = TextEditingController();
  final _allergyInput = TextEditingController();

  final List<AllergyTag> _allergies = [];
  String _allergySeverity = 'Mild';

  @override
  void dispose() {
    _chiefComplaint.dispose();
    _hpi.dispose();
    _pmh.dispose();
    _familyHistory.dispose();
    _allergyInput.dispose();
    super.dispose();
  }

  void _addAllergy() {
    final name = _allergyInput.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _allergies.add(AllergyTag(name: name, severity: _allergySeverity));
      _allergyInput.clear();
    });
  }

  void _save() {
    final parts = <String>[
      if (_chiefComplaint.text.trim().isNotEmpty)
        'Chief complaint: ${_chiefComplaint.text.trim()}',
      if (_hpi.text.trim().isNotEmpty) 'HPI: ${_hpi.text.trim()}',
      if (_pmh.text.trim().isNotEmpty) 'Past medical history: ${_pmh.text.trim()}',
      if (_familyHistory.text.trim().isNotEmpty)
        'Family history: ${_familyHistory.text.trim()}',
      if (_allergies.isNotEmpty)
        'Allergies: ${_allergies.map((a) => '${a.name} (${a.severity})').join(', ')}',
    ];

    final summary = parts.join('\n');
    final appointmentId = widget.patient.appointmentId;
    if (appointmentId == null || appointmentId.isEmpty) {
      AppToast.info(context, 'No appointment linked — clinical notes could not be saved.');
      return;
    }

    SharedAppointmentsStore.instance.saveConsultationOutcome(
      recordId: appointmentId,
      diagnosis: _chiefComplaint.text.trim().isNotEmpty ? _chiefComplaint.text.trim() : null,
      clinicalNotes: summary.isNotEmpty ? summary : null,
    );

    showClinicalToast(context, 'Clinical notes saved to EMR');
  }

  @override
  Widget build(BuildContext context) {
    final visitDate = DateFormat('dd MMM yyyy').format(DateTime.now());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClinicalSectionCard(
          title: 'Visit Info',
          child: _InfoLine(label: 'Visit date', value: visitDate),
        ),
        ClinicalSectionCard(
          title: 'History',
          child: Column(
            children: [
              TextFormField(
                controller: _chiefComplaint,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Chief complaint',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hpi,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'History of present illness',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pmh,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Past medical history',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _familyHistory,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Family history',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        ClinicalSectionCard(
          title: 'Allergies',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _allergyInput,
                      decoration: const InputDecoration(
                        labelText: 'Add allergy',
                        hintText: 'e.g. Penicillin',
                      ),
                      onFieldSubmitted: (_) => _addAllergy(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _allergySeverity,
                      isExpanded: true,
                      items: ClinicalMockData.allergySeverities
                          .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _allergySeverity = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LabeledAddButton(
                label: '+ Add Allergy',
                onPressed: _addAllergy,
              ),
              if (_allergies.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _allergies.map((a) {
                    final color = switch (a.severity) {
                      'Severe' => const Color(0xFFDC2626),
                      'Moderate' => const Color(0xFFEA580C),
                      _ => const Color(0xFF2563EB),
                    };
                    return InputChip(
                      label: Text('${a.name} (${a.severity})'),
                      deleteIconColor: color,
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: color),
                      side: BorderSide(color: color.withValues(alpha: 0.4)),
                      onDeleted: () => setState(() => _allergies.remove(a)),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('Save Clinical Notes'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context))),
        Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
