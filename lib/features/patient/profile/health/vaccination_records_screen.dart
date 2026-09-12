import '../../../../core/firebase/firestore_service.dart';
import '../../../../core/notifications/app_toast.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/session/patient_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/confirm_delete_dialog.dart';
import '../../../../widgets/labeled_remove_button.dart';
import '../../records/models/health_record_models.dart';
import '../data/patient_profile_mock.dart';
import '../widgets/patient_profile_form_styles.dart';

class _VaccinationEntry {
  const _VaccinationEntry({
    required this.id,
    required this.name,
    required this.date,
    this.dose,
    this.notes,
  });

  final String id;
  final String name;
  final DateTime date;
  final String? dose;
  final String? notes;
}

class VaccinationRecordsScreen extends StatefulWidget {
  const VaccinationRecordsScreen({super.key});

  @override
  State<VaccinationRecordsScreen> createState() => _VaccinationRecordsScreenState();
}

class _VaccinationRecordsScreenState extends State<VaccinationRecordsScreen> {
  final List<_VaccinationEntry> _entries = [];
  bool _loading = true;
  bool _showAddForm = false;
  final _nameController = TextEditingController();
  final _doseController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _dateGiven = DateTime.now();
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _doseController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _openAddForm() {
    setState(() {
      _showAddForm = true;
      _nameError = null;
    });
  }

  void _closeAddForm() {
    setState(() {
      _showAddForm = false;
      _nameController.clear();
      _doseController.clear();
      _notesController.clear();
      _dateGiven = DateTime.now();
      _nameError = null;
    });
  }

  Future<void> _pickDateGiven() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateGiven,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateGiven = picked);
  }

  List<_VaccinationEntry> _entriesFromMock() {
    return PatientProfileMock.vaccinations
        .asMap()
        .entries
        .map(
          (e) => _VaccinationEntry(
            id: 'mock_${e.key}_${e.value.date.millisecondsSinceEpoch}',
            name: e.value.name,
            date: e.value.date,
          ),
        )
        .toList();
  }

  void _syncMockFromEntries() {
    PatientProfileMock.vaccinations
      ..clear()
      ..addAll(_entries.map((e) => (name: e.name, date: e.date)));
  }

  _VaccinationEntry? _entryFromHealthRecord(HealthRecord record) {
    String name = record.title;
    String? dose;
    String? userNotes;
    DateTime date = record.date;

    final rawNotes = record.notes;
    if (rawNotes != null && rawNotes.trim().isNotEmpty) {
      try {
        final map = jsonDecode(rawNotes) as Map<String, dynamic>;
        if (map['kind'] == 'vaccination') {
          name = map['name'] as String? ?? name;
          dose = map['dose'] as String?;
          userNotes = map['userNotes'] as String?;
          final dateStr = map['dateGiven'] as String?;
          if (dateStr != null) {
            date = DateTime.tryParse(dateStr) ?? date;
          }
        }
      } catch (_) {}
    }

    if (name.startsWith('Vaccination — ')) {
      name = name.substring('Vaccination — '.length);
    }

    return _VaccinationEntry(
      id: record.id,
      name: name,
      date: date,
      dose: dose,
      notes: userNotes,
    );
  }

  HealthRecord _healthRecordFromEntry(_VaccinationEntry entry) {
    final payload = <String, dynamic>{
      'kind': 'vaccination',
      'name': entry.name,
      'dateGiven': entry.date.toIso8601String(),
      if (entry.dose != null && entry.dose!.isNotEmpty) 'dose': entry.dose,
      if (entry.notes != null && entry.notes!.isNotEmpty) 'userNotes': entry.notes,
    };

    return HealthRecord(
      id: entry.id,
      title: 'Vaccination — ${entry.name}',
      type: HealthRecordType.vaccination,
      date: entry.date,
      source: RecordSource.selfUploaded,
      fileName: 'vaccination',
      notes: jsonEncode(payload),
    );
  }

  Future<void> _loadRecords() async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(_entriesFromMock());
        _loading = false;
      });
      return;
    }

    try {
      final records = await FirestoreService.instance.patientProfile.fetchHealthRecords(patientId);
      final vaccinations = records
          .where((r) => r.type == HealthRecordType.vaccination)
          .map(_entryFromHealthRecord)
          .whereType<_VaccinationEntry>()
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(vaccinations);
        _syncMockFromEntries();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(_entriesFromMock());
        _loading = false;
      });
      AppToast.info(context, 'Could not load vaccination records.');
    }
  }

  Future<void> _saveVaccination() async {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() => _nameError = 'Enter at least 2 characters');
      return;
    }

    final dose = _doseController.text.trim();
    final notes = _notesController.text.trim();

    final entry = _VaccinationEntry(
      id: 'vac${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      date: DateTime(_dateGiven.year, _dateGiven.month, _dateGiven.day),
      dose: dose.isEmpty ? null : dose,
      notes: notes.isEmpty ? null : notes,
    );

    setState(() {
      _entries.insert(0, entry);
      _syncMockFromEntries();
      _showAddForm = false;
      _nameController.clear();
      _doseController.clear();
      _notesController.clear();
      _dateGiven = DateTime.now();
      _nameError = null;
    });

    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isNotEmpty) {
      try {
        await FirestoreService.instance.patientProfile.saveHealthRecord(
          patientId,
          _healthRecordFromEntry(entry),
        );
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _entries.removeWhere((e) => e.id == entry.id);
          _syncMockFromEntries();
        });
        AppToast.info(context, 'Failed to save vaccination. Please try again.');
        return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Vaccination saved'),
        backgroundColor: Color(0xFF16A34A),
      ),
    );
  }

  Widget _buildAddForm() {
    return PatientProfileFormStyles.contentSurface(context: context, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add Vaccination',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: _closeAddForm,
                icon: Icon(Icons.close, color: AppColors.textSecondaryOf(context)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: PatientProfileFormStyles.fieldDecoration(context, 
              labelText: 'Vaccine name',
              isRequired: true,
            ).copyWith(errorText: _nameError),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 12),
          PatientProfileFormStyles.dobPickerRow(
          context: context,
            label: 'Date given',
            isRequired: true,
            valueText: DateFormat('dd MMM yyyy').format(_dateGiven),
            onTap: _pickDateGiven,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _doseController,
            decoration: PatientProfileFormStyles.fieldDecoration(context, 
              labelText: 'Dose (optional)',
              hintText: 'e.g. 1st, 2nd, Booster',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: PatientProfileFormStyles.fieldDecoration(context, 
              labelText: 'Notes (optional)',
              alignLabelWithHint: true,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          PatientProfileFormStyles.cardActionButton(
            onPressed: _saveVaccination,
            label: 'Save',
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(_VaccinationEntry entry) async {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index < 0) return;

    setState(() {
      _entries.removeAt(index);
      _syncMockFromEntries();
    });

    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isNotEmpty && !entry.id.startsWith('mock_')) {
      try {
        await FirestoreService.instance.patientProfile.deleteHealthRecord(entry.id);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _entries.insert(index, entry);
          _syncMockFromEntries();
        });
        AppToast.info(context, 'Failed to delete vaccination. Please try again.');
        return;
      }
    }

    if (!mounted) return;
    AppToast.info(context, 'Vaccination removed');
  }

  Future<bool> _confirmDelete(_VaccinationEntry entry) {
    return showConfirmDeleteDialog(
      context,
      title: 'Delete vaccination?',
      message: 'Remove ${entry.name} from your records?',
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        const FaIcon(
          FontAwesomeIcons.syringe,
          size: 48,
          color: AppColors.patientTeal,
        ),
        const SizedBox(height: 16),
        Text(
          'No vaccination records yet',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add your vaccination history to keep track',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 24),
        if (!_showAddForm)
          PatientProfileFormStyles.outlinedAddButton(
            label: 'Add Vaccination',
            onPressed: _openAddForm,
          ),
      ],
    );
  }

  Widget _buildRecordTile(_VaccinationEntry entry) {
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Delete',
          style: GoogleFonts.inter(
            color: AppColors.surfaceOf(context),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(entry),
      onDismissed: (_) => _deleteEntry(entry),
      child: PatientProfileFormStyles.recordItemCard(
        context: context,
        child: Row(
          children: [
            const Icon(Icons.vaccines, color: Color(0xFF16A34A), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  Text(
                    DateFormat('dd MMM yyyy').format(entry.date),
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                  ),
                  if (entry.dose != null && entry.dose!.isNotEmpty)
                    Text(
                      entry.dose!,
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                    ),
                  if (entry.notes != null && entry.notes!.isNotEmpty)
                    Text(
                      entry.notes!,
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            LabeledRemoveButton(
              label: 'Delete',
              onPressed: () async {
                if (await _confirmDelete(entry)) {
                  await _deleteEntry(entry);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('Vaccination Records', context: context),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.patientTeal))
          : PatientProfileFormStyles.constrainedScrollBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showAddForm) ...[
                    _buildAddForm(),
                    const SizedBox(height: 16),
                  ],
                  if (_entries.isEmpty)
                    PatientProfileFormStyles.contentSurface(context: context, child: _buildEmptyState())
                  else ...[
                    PatientProfileFormStyles.contentSurface(context: context, child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PatientProfileFormStyles.sectionHeader('Your vaccinations'),
                          const SizedBox(height: 16),
                          ..._entries.map(_buildRecordTile),
                        ],
                      ),
                    ),
                    if (!_showAddForm) ...[
                      const SizedBox(height: 16),
                      PatientProfileFormStyles.outlinedAddButton(
                        label: 'Add Vaccination',
                        onPressed: _openAddForm,
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}
