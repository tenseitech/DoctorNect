import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../profile/data/doctor_profile_store.dart';
import '../models/clinical_models.dart';
import 'prescription_header_helper.dart';
import 'prescription_pdf_service.dart';

class PrescriptionPreviewModal {
  static void show(BuildContext context, {required PrescriptionDraft draft}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PrescriptionPreviewPage(draft: draft),
      ),
    );
  }
}

class _PrescriptionPreviewPage extends StatefulWidget {
  const _PrescriptionPreviewPage({required this.draft});

  final PrescriptionDraft draft;

  @override
  State<_PrescriptionPreviewPage> createState() => _PrescriptionPreviewPageState();
}

class _PrescriptionPreviewPageState extends State<_PrescriptionPreviewPage> {
  String _timings = PrescriptionHeaderHelper.fallbackTimings;
  bool _busy = false;

  PrescriptionDraft get _draft => widget.draft;

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

  Future<void> _runAction(Future<void> Function() action, {String? errorLabel}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        AppToast.info(context, '${errorLabel ?? 'Action'} failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showShareOptions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Share prescription',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366)),
                title: Text('WhatsApp', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                subtitle: Text(
                  kIsWeb ? 'Share summary via WhatsApp' : 'Share PDF via WhatsApp',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _runAction(
                    () => PrescriptionPdfService.shareViaWhatsApp(_draft, context: context),
                    errorLabel: 'WhatsApp share',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.email_outlined, color: AppColors.doctorBlue),
                title: Text('Email', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                subtitle: Text(
                  kIsWeb ? 'Open email with prescription summary' : 'Share PDF via email app',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _runAction(
                    () => PrescriptionPdfService.shareViaEmail(_draft),
                    errorLabel: 'Email share',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    // Prefer the snapshot values saved in the prescription (visible to any
    // viewer, not just the prescribing doctor).  Fall back to DoctorProfileStore
    // only when the doctor is viewing their own fresh draft.
    final profile = DoctorProfileStore.instance.profile;
    final hasDoctorSnapshot = draft.doctorName.isNotEmpty;

    final displayDoctorName = PrescriptionHeaderHelper.doctorNameForDraft(
      draft,
      fallback: DoctorProfileStore.displayNameWithPrefix,
    );
    final displaySpecialization = hasDoctorSnapshot
        ? draft.doctorSpecialization
        : profile.specialization;
    final displayQualifications = hasDoctorSnapshot
        ? draft.doctorQualifications
        : PrescriptionHeaderHelper.qualificationsLine(profile);
    final displayRegNumber = hasDoctorSnapshot
        ? draft.doctorRegNumber
        : profile.councilNumber;
    final displayClinicName = hasDoctorSnapshot
        ? draft.clinicName
        : profile.clinicName;
    final displayAddress = hasDoctorSnapshot
        ? draft.clinicAddress
        : PrescriptionHeaderHelper.clinicAddressLine(profile);
    final displayPhone = hasDoctorSnapshot
        ? draft.doctorPhone
        : profile.mobile;

    final date = DateFormat('dd MMM yyyy').format(draft.prescriptionDate);

    return Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      appBar: AppBar(
        title: const Text('Prescription Preview'),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: _busy ? null : _showShareOptions,
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download PDF',
            onPressed: _busy
                ? null
                : () => _runAction(
                      () => PrescriptionPdfService.downloadPdf(_draft),
                      errorLabel: 'Download',
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print',
            onPressed: _busy
                ? null
                : () => _runAction(
                      () => PrescriptionPdfService.printPrescription(_draft),
                      errorLabel: 'Print',
                    ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 595,
              minWidth: 0,
              minHeight: 842,
            ),
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (displayClinicName.isNotEmpty)
                  Text(displayClinicName,
                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
                if (displayAddress.isNotEmpty)
                  Text(displayAddress,
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context))),
                if (displayPhone.isNotEmpty)
                  Text('Phone: $displayPhone',
                      style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondaryOf(context))),
                Text('Consultation: $_timings',
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondaryOf(context))),
                const Divider(height: 24),
                Text(
                  displayQualifications.isNotEmpty
                      ? '$displayDoctorName · $displayQualifications'
                      : displayDoctorName,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (displaySpecialization.isNotEmpty || displayRegNumber.isNotEmpty)
                  Text(
                    [
                      if (displaySpecialization.isNotEmpty) displaySpecialization,
                      if (displayRegNumber.isNotEmpty) 'Reg: $displayRegNumber',
                    ].join(' · '),
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context)),
                  ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Patient: ${draft.patient.patientName}',
                            style: GoogleFonts.inter(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Age: ${draft.patient.age} yrs · ${draft.patient.gender ?? '—'} · ID: ${draft.patientId}',
                            style: GoogleFonts.inter(fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (draft.vitals.weightKg.isNotEmpty)
                            Text(
                              'Weight: ${draft.vitals.weightKg} kg',
                              style: GoogleFonts.inter(fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Date: $date',
                            style: GoogleFonts.inter(fontSize: 11),
                            textAlign: TextAlign.end,
                          ),
                          Text(
                            'Rx ID: ${draft.prescriptionId}',
                            style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondaryOf(context)),
                            textAlign: TextAlign.end,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_hasVitals) ...[
                  const SizedBox(height: 12),
                  Text('Vitals', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(_vitalsLine, style: GoogleFonts.inter(fontSize: 10)),
                ],
                if (draft.chiefComplaint.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Chief Complaint', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(draft.chiefComplaint, style: GoogleFonts.inter(fontSize: 10)),
                ],
                if (draft.generalExamination.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('General examination',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(draft.generalExamination, style: GoogleFonts.inter(fontSize: 10)),
                ],
                const SizedBox(height: 12),
                Text('Diagnosis (${draft.diagnosisType})',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                _labeledPreviewLine('Primary', draft.primaryDiagnosis),
                if (draft.secondaryDiagnosis.isNotEmpty)
                  _labeledPreviewLine('Secondary', draft.secondaryDiagnosis),
                if (draft.symptoms.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Symptoms', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(draft.symptoms, style: GoogleFonts.inter(fontSize: 10)),
                ],
                if (draft.symptomDuration.isNotEmpty)
                  _labeledPreviewLine('Duration', draft.symptomDuration),
                if (draft.pastHistory.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Past medical history',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(draft.pastHistory, style: GoogleFonts.inter(fontSize: 10)),
                ],
                if (draft.allergies.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Allergies: ${draft.allergies}',
                      style: GoogleFonts.inter(fontSize: 10, color: AppColors.error)),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('℞', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text('Medicines',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                if (draft.validMedicines.isNotEmpty) _buildMedicinesTable(draft),
                if (draft.validInvestigations.isNotEmpty || draft.bodyParts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Investigations / Tests',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ..._buildInvestigationTables(draft),
                  if (draft.bodyParts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Body Part / Region',
                        style: GoogleFonts.inter(
                            fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                    const SizedBox(height: 4),
                    _buildBodyPartsTable(draft.bodyParts),
                  ],
                ],
                if (_hasAdvice(draft)) ...[
                  const SizedBox(height: 12),
                  Text('Advice', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  if (draft.dietAdvice.isNotEmpty)
                    _labeledPreviewLine('Diet', draft.dietAdvice),
                  if (draft.activityRestrictions.isNotEmpty)
                    _labeledPreviewLine('Rest & activity', draft.activityRestrictions),
                  if (draft.lifestyleAdvice.isNotEmpty)
                    _labeledPreviewLine('Lifestyle', draft.lifestyleAdvice),
                  if (draft.generalAdvice.isNotEmpty)
                    _labeledPreviewLine('General', draft.generalAdvice),
                ],
                if (draft.nextVisit != null || draft.followUpNote.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Follow-up', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  if (draft.nextVisit != null)
                    _labeledPreviewLine(
                      'Next visit',
                      DateFormat('dd MMM yyyy').format(draft.nextVisit!),
                    ),
                  if (draft.followUpNote.isNotEmpty)
                    _labeledPreviewLine('Condition note', draft.followUpNote),
                ],
                if (draft.referrals.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Referred to',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ...draft.referrals.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        r.reason.isNotEmpty ? '${r.displayTitle} — ${r.reason}' : r.displayTitle,
                        style: GoogleFonts.inter(fontSize: 10),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                if (draft.validityDate != null)
                  _labeledPreviewLine(
                    'Valid until',
                    DateFormat('dd MMM yyyy').format(draft.validityDate!),
                  ),
                const SizedBox(height: 40),
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(width: 140, height: 1, color: AppColors.textPrimaryOf(context)),
                      const SizedBox(height: 4),
                      Text(displayDoctorName,
                          style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic)),
                      if (displayPhone.isNotEmpty)
                        Text('Phone: $displayPhone',
                            style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondaryOf(context))),
                      Text(DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()),
                          style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondaryOf(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  bool _hasAdvice(PrescriptionDraft draft) {
    return draft.dietAdvice.isNotEmpty ||
        draft.activityRestrictions.isNotEmpty ||
        draft.lifestyleAdvice.isNotEmpty ||
        draft.generalAdvice.isNotEmpty;
  }

  Widget _labeledPreviewLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(fontSize: 10, color: AppColors.textPrimaryOf(context)),
          children: [
            TextSpan(
              text: '$label: ',
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  bool get _hasVitals {
    final v = widget.draft.vitals;
    return v.bloodPressure.isNotEmpty ||
        v.temperature.isNotEmpty ||
        v.pulse.isNotEmpty ||
        v.spo2.isNotEmpty ||
        v.heightCm.isNotEmpty ||
        v.respiratoryRate.isNotEmpty;
  }

  String get _vitalsLine {
    final v = widget.draft.vitals;
    final parts = <String>[];
    if (v.bloodPressure.isNotEmpty) parts.add('BP ${v.bloodPressure}');
    if (v.temperature.isNotEmpty) parts.add('Temp ${v.temperature}°F');
    if (v.pulse.isNotEmpty) parts.add('Pulse ${v.pulse} bpm');
    if (v.spo2.isNotEmpty) parts.add('SpO2 ${v.spo2}%');
    if (v.heightCm.isNotEmpty) parts.add('Ht ${v.heightCm} cm');
    if (v.respiratoryRate.isNotEmpty) parts.add('RR ${v.respiratoryRate}/min');
    return parts.join(' · ');
  }

  static const _tableBorder = Color(0xFFCBD5E1);
  static const _headerBg = Color(0xFFF1F5F9);

  TableRow _headerRow(List<String> cells) {
    return TableRow(
      decoration: const BoxDecoration(color: _headerBg),
      children: cells
          .map((c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(
                  c,
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF334155),
                    letterSpacing: 0.3,
                  ),
                ),
              ))
          .toList(),
    );
  }

  TableRow _bodyRow(List<String> cells, {bool boldFirst = false}) {
    return TableRow(
      children: List.generate(cells.length, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(
            cells[i],
            style: GoogleFonts.inter(
              fontSize: 9.5,
              height: 1.35,
              fontWeight: (boldFirst && i == 1) ? FontWeight.w600 : FontWeight.w400,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildMedicinesTable(PrescriptionDraft d) {
    final rows = <TableRow>[
      _headerRow(const ['#', 'Medicine', 'Dosage', 'Frequency', 'Timing', 'Duration', 'Qty', 'Notes']),
    ];

    for (var i = 0; i < d.validMedicines.length; i++) {
      final m = d.validMedicines[i];
      final medCell = '${m.name}${m.form.isNotEmpty ? '\n(${m.form})' : ''}';
      final dur = m.durationLabel.trim();
      final notesParts = <String>[];
      if (m.isSos) notesParts.add('SOS');
      if (!m.substituteAllowed) notesParts.add('No substitute');
      if (m.specialInstructions.isNotEmpty) notesParts.add(m.specialInstructions);
      final notes = notesParts.join(' · ');

      rows.add(_bodyRow([
        '${i + 1}',
        medCell,
        m.dosageLabel,
        m.frequencyLabel,
        m.instructions,
        dur,
        m.quantity,
        notes,
      ], boldFirst: true));
    }

    return Table(
      border: TableBorder.all(color: _tableBorder, width: 0.6),
      columnWidths: const {
        0: FixedColumnWidth(26),
        1: FlexColumnWidth(2.4),
        2: FlexColumnWidth(1.4),
        3: FlexColumnWidth(1.4),
        4: FlexColumnWidth(1.5),
        5: FlexColumnWidth(1.2),
        6: FixedColumnWidth(42),
        7: FlexColumnWidth(2.0),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  List<Widget> _buildInvestigationTables(PrescriptionDraft d) {
    if (d.validInvestigations.isEmpty) return const [];

    final labs = d.validInvestigations
        .where((e) =>
            e.type == InvestigationType.lab ||
            (e.type == InvestigationType.custom && e.group == 'lab'))
        .toList();
    final rads = d.validInvestigations
        .where((e) =>
            e.type == InvestigationType.radiology ||
            (e.type == InvestigationType.custom && e.group == 'radiology'))
        .toList();

    Widget buildSection(String title, List<InvestigationEntry> items) {
      // Group by category for sub-headers but keep them inside a single table.
      final grouped = <String, List<InvestigationEntry>>{};
      for (final e in items) {
        final key = e.type == InvestigationType.custom
            ? 'Custom'
            : (e.group.isEmpty ? 'Other' : e.group);
        grouped.putIfAbsent(key, () => []).add(e);
      }

      final rows = <TableRow>[
        _headerRow(const ['#', 'Category', 'Test Name', 'Notes / Reason']),
      ];

      var index = 1;
      grouped.forEach((category, list) {
        for (final i in list) {
          rows.add(_bodyRow([
            '$index',
            category.toUpperCase(),
            i.name,
            i.notes,
          ], boldFirst: true));
          index++;
        }
      });

      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF334155),
                ),
              ),
            ),
            Table(
              border: TableBorder.all(color: _tableBorder, width: 0.6),
              columnWidths: const {
                0: FixedColumnWidth(26),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(2.6),
                3: FlexColumnWidth(2.0),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: rows,
            ),
          ],
        ),
      );
    }

    return [
      if (labs.isNotEmpty) buildSection('Lab Tests', labs),
      if (rads.isNotEmpty) buildSection('Radiology', rads),
    ];
  }

  Widget _buildBodyPartsTable(List<String> parts) {
    final rows = <TableRow>[
      _headerRow(const ['#', 'Region']),
    ];
    for (var i = 0; i < parts.length; i++) {
      rows.add(_bodyRow(['${i + 1}', parts[i]]));
    }
    return Table(
      border: TableBorder.all(color: _tableBorder, width: 0.6),
      columnWidths: const {
        0: FixedColumnWidth(26),
        1: FlexColumnWidth(1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }
}
