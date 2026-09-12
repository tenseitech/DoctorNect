import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/session/doctor_session.dart';
import '../../profile/data/doctor_profile_store.dart';
import '../models/clinical_models.dart';
import 'prescription_header_helper.dart';

class PrescriptionPdfService {
  static Future<void> printPrescription(PrescriptionDraft draft) async {
    final bytes = await buildPdfBytes(draft);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: draft.prescriptionId,
    );
  }

  static Future<void> sharePdf(PrescriptionDraft draft) async {
    final bytes = await buildPdfBytes(draft);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${draft.prescriptionId}.pdf',
    );
  }

  static Future<void> downloadPdf(PrescriptionDraft draft) async {
    await sharePdf(draft);
  }

  static String shareSummaryText(PrescriptionDraft draft) {
    final doctor = PrescriptionHeaderHelper.doctorNameForDraft(
      draft,
      fallback: DoctorProfileStore.displayNameWithPrefix,
    );
    final date = DateFormat('dd MMM yyyy').format(draft.prescriptionDate);
    final meds = draft.validMedicines
        .map((m) {
          final dosage = m.dosageLabel.trim();
          return dosage.isEmpty ? m.name.trim() : '${m.name.trim()} ($dosage)';
        })
        .join('\n• ');

    final buffer = StringBuffer()
      ..writeln('Prescription — ${draft.patient.patientName}')
      ..writeln('Date: $date · Rx ID: ${draft.prescriptionId}')
      ..writeln('Doctor: $doctor')
      ..writeln('Diagnosis: ${draft.primaryDiagnosis.trim()}');

    if (meds.isNotEmpty) {
      buffer.writeln('\nMedicines:\n• $meds');
    }

    buffer.write('\n— Shared via DoctorNect');
    return buffer.toString().trim();
  }

  /// Shares the prescription as a PDF file (all platforms) via the native
  /// share sheet — pick WhatsApp there.
  static Future<void> shareViaWhatsApp(
    PrescriptionDraft draft, {
    BuildContext? context,
  }) async {
    await sharePdf(draft);
  }

  /// Shares the prescription as a PDF file (all platforms) via the native
  /// share sheet — pick the email app there.
  static Future<void> shareViaEmail(PrescriptionDraft draft) async {
    await sharePdf(draft);
  }

  static Future<Uint8List> buildPdfBytes(PrescriptionDraft draft) async {
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final italicFont = await PdfGoogleFonts.notoSansItalic();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: boldFont,
        italic: italicFont,
      ),
    );
    final profile = DoctorProfileStore.instance.profile;
    final hasDoctorSnapshot = draft.doctorName.isNotEmpty;
    final doctorId = hasDoctorSnapshot ? draft.doctorId : DoctorSession.loggedInDoctorId;
    await PrescriptionHeaderHelper.loadConsultationTimings(doctorId);
    final qualifications = hasDoctorSnapshot
        ? draft.doctorQualifications
        : PrescriptionHeaderHelper.qualificationsLine(profile);
    final timings = PrescriptionHeaderHelper.consultationTimings;
    final date = DateFormat('dd MMM yyyy').format(draft.prescriptionDate);
    final displayDoctorName = PrescriptionHeaderHelper.doctorNameForDraft(
      draft,
      fallback: DoctorProfileStore.displayNameWithPrefix,
    );
    final displaySpecialization = hasDoctorSnapshot
        ? draft.doctorSpecialization
        : profile.specialization;
    final displayRegNumber = hasDoctorSnapshot
        ? draft.doctorRegNumber
        : profile.councilNumber;
    final displayClinicName = hasDoctorSnapshot ? draft.clinicName : profile.clinicName;
    final address = hasDoctorSnapshot
        ? draft.clinicAddress
        : PrescriptionHeaderHelper.clinicAddressLine(profile);
    final contact = hasDoctorSnapshot
        ? (draft.doctorPhone.isNotEmpty ? 'Phone: ${draft.doctorPhone}' : '')
        : PrescriptionHeaderHelper.contactDetailsLine(profile);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          if (displayClinicName.isNotEmpty) ...[
            pw.Text(
              displayClinicName,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
          ],
          if (address.isNotEmpty)
            pw.Text(address, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          if (contact.isNotEmpty)
            pw.Text(contact, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text(
            'Consultation: $timings',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.Divider(),
          pw.Text(
            qualifications.isNotEmpty
                ? '$displayDoctorName · $qualifications'
                : displayDoctorName,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          if (displaySpecialization.isNotEmpty || displayRegNumber.isNotEmpty)
            pw.Text(
              [
                if (displaySpecialization.isNotEmpty) displaySpecialization,
                if (displayRegNumber.isNotEmpty) 'Reg: $displayRegNumber',
              ].join(' · '),
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Patient: ${draft.patient.patientName}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(
                    'Age: ${draft.patient.age} yrs · ${draft.patient.gender ?? '-'} · ID: ${draft.patientId}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  if (draft.vitals.weightKg.isNotEmpty)
                    pw.Text('Weight: ${draft.vitals.weightKg} kg', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Date: $date', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(
                    'Rx ID: ${draft.prescriptionId}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  ),
                ],
              ),
            ],
          ),
          if (_hasVitals(draft)) ...[
            pw.SizedBox(height: 8),
            pw.Text('Vitals', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(_vitalsLine(draft), style: const pw.TextStyle(fontSize: 9)),
          ],
          if (draft.chiefComplaint.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Chief Complaint', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(draft.chiefComplaint, style: const pw.TextStyle(fontSize: 9)),
          ],
          if (draft.generalExamination.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _sectionText('General examination', draft.generalExamination),
          ],
          pw.SizedBox(height: 8),
          pw.Text(
            'Diagnosis (${draft.diagnosisType})',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          _labeledLine('Primary', draft.primaryDiagnosis),
          if (draft.secondaryDiagnosis.isNotEmpty)
            _labeledLine('Secondary', draft.secondaryDiagnosis),
          if (draft.symptoms.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            _sectionText('Symptoms', draft.symptoms),
          ],
          if (draft.symptomDuration.isNotEmpty)
            _labeledLine('Duration', draft.symptomDuration),
          if (draft.pastHistory.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            _sectionText('Past medical history', draft.pastHistory),
          ],
          if (draft.allergies.isNotEmpty)
            pw.Text(
              'Allergies: ${draft.allergies}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.red800),
            ),
          pw.SizedBox(height: 12),
          pw.Text('Rx Medicines', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (draft.validMedicines.isNotEmpty) _medicinesTable(draft),
          if (draft.validInvestigations.isNotEmpty || draft.bodyParts.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'Investigations / Tests',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            ..._investigationTables(draft),
            if (draft.bodyParts.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                'Body Part / Region',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              _bodyPartsTable(draft.bodyParts),
            ],
          ],
          if (_hasAdvice(draft)) ...[
            pw.SizedBox(height: 12),
            pw.Text('Advice', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            if (draft.dietAdvice.isNotEmpty) _labeledLine('Diet', draft.dietAdvice),
            if (draft.activityRestrictions.isNotEmpty)
              _labeledLine('Rest & activity', draft.activityRestrictions),
            if (draft.lifestyleAdvice.isNotEmpty) _labeledLine('Lifestyle', draft.lifestyleAdvice),
            if (draft.generalAdvice.isNotEmpty) _labeledLine('General', draft.generalAdvice),
          ],
          if (draft.nextVisit != null || draft.followUpNote.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Follow-up', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            if (draft.nextVisit != null)
              _labeledLine(
                'Next visit',
                DateFormat('dd MMM yyyy').format(draft.nextVisit!),
              ),
            if (draft.followUpNote.isNotEmpty)
              _labeledLine('Condition note', draft.followUpNote),
          ],
          if (draft.validityDate != null)
            _labeledLine(
              'Valid until',
              DateFormat('dd MMM yyyy').format(draft.validityDate!),
            ),
          pw.SizedBox(height: 24),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(width: 120, height: 0.5, color: PdfColors.black),
                pw.SizedBox(height: 4),
                pw.Text(
                  displayDoctorName,
                  style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
                ),
                if (contact.isNotEmpty)
                  pw.Text(
                    contact,
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  ),
                pw.Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()),
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  static bool _hasVitals(PrescriptionDraft draft) {
    final v = draft.vitals;
    return v.bloodPressure.isNotEmpty ||
        v.temperature.isNotEmpty ||
        v.pulse.isNotEmpty ||
        v.spo2.isNotEmpty ||
        v.heightCm.isNotEmpty ||
        v.respiratoryRate.isNotEmpty;
  }

  static String _vitalsLine(PrescriptionDraft draft) {
    final v = draft.vitals;
    final parts = <String>[];
    if (v.bloodPressure.isNotEmpty) parts.add('BP ${v.bloodPressure}');
    if (v.temperature.isNotEmpty) parts.add('Temp ${v.temperature}°F');
    if (v.pulse.isNotEmpty) parts.add('Pulse ${v.pulse} bpm');
    if (v.spo2.isNotEmpty) parts.add('SpO2 ${v.spo2}%');
    if (v.heightCm.isNotEmpty) parts.add('Ht ${v.heightCm} cm');
    if (v.respiratoryRate.isNotEmpty) parts.add('RR ${v.respiratoryRate}/min');
    return parts.join(' · ');
  }

  static bool _hasAdvice(PrescriptionDraft draft) {
    return draft.dietAdvice.isNotEmpty ||
        draft.activityRestrictions.isNotEmpty ||
        draft.lifestyleAdvice.isNotEmpty ||
        draft.generalAdvice.isNotEmpty;
  }

  static pw.Widget _labeledLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _sectionText(String heading, String body) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(heading, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.Text(body, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  static pw.Widget _medicinesTable(PrescriptionDraft draft) {
    final rows = <List<String>>[
      const ['#', 'Medicine', 'Dosage', 'Frequency', 'Timing', 'Duration', 'Qty', 'Notes'],
    ];

    for (var i = 0; i < draft.validMedicines.length; i++) {
      final m = draft.validMedicines[i];
      final medCell = '${m.name}${m.form.isNotEmpty ? '\n(${m.form})' : ''}';
      final dur = m.durationLabel.trim();
      final notesParts = <String>[];
      if (m.isSos) notesParts.add('SOS');
      if (!m.substituteAllowed) notesParts.add('No substitute');
      if (m.specialInstructions.isNotEmpty) notesParts.add(m.specialInstructions);

      rows.add([
        '${i + 1}',
        medCell,
        m.dosageLabel,
        m.frequencyLabel,
        m.instructions,
        dur,
        m.quantity,
        notesParts.join(' · '),
      ]);
    }

    return _table(rows, flex: const [0.4, 2.4, 1.2, 1.2, 1.3, 1.0, 0.6, 1.8]);
  }

  static List<pw.Widget> _investigationTables(PrescriptionDraft draft) {
    final labs = draft.validInvestigations
        .where((e) =>
            e.type == InvestigationType.lab ||
            (e.type == InvestigationType.custom && e.group == 'lab'))
        .toList();
    final rads = draft.validInvestigations
        .where((e) =>
            e.type == InvestigationType.radiology ||
            (e.type == InvestigationType.custom && e.group == 'radiology'))
        .toList();

    pw.Widget buildSection(String title, List<InvestigationEntry> items) {
      final grouped = <String, List<InvestigationEntry>>{};
      for (final e in items) {
        final key = e.type == InvestigationType.custom
            ? 'Custom'
            : (e.group.isEmpty ? 'Other' : e.group);
        grouped.putIfAbsent(key, () => []).add(e);
      }

      final rows = <List<String>>[
        const ['#', 'Category', 'Test Name', 'Notes / Reason'],
      ];
      var index = 1;
      grouped.forEach((category, list) {
        for (final i in list) {
          rows.add(['$index', category.toUpperCase(), i.name, i.notes]);
          index++;
        }
      });

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          _table(rows, flex: const [0.4, 1.4, 2.6, 2.0]),
        ],
      );
    }

    return [
      if (labs.isNotEmpty) buildSection('Lab Tests', labs),
      if (labs.isNotEmpty && rads.isNotEmpty) pw.SizedBox(height: 8),
      if (rads.isNotEmpty) buildSection('Radiology', rads),
    ];
  }

  static pw.Widget _bodyPartsTable(List<String> parts) {
    final rows = <List<String>>[
      const ['#', 'Region'],
    ];
    for (var i = 0; i < parts.length; i++) {
      rows.add(['${i + 1}', parts[i]]);
    }
    return _table(rows, flex: const [0.4, 1]);
  }

  static pw.Widget _table(List<List<String>> rows, {required List<double> flex}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        for (var i = 0; i < flex.length; i++)
          i: flex[i] <= 0.5 ? const pw.FixedColumnWidth(22) : pw.FlexColumnWidth(flex[i]),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows.asMap().entries.map((entry) {
        final isHeader = entry.key == 0;
        return pw.TableRow(
          decoration: isHeader
              ? const pw.BoxDecoration(color: PdfColors.grey200)
              : null,
          children: entry.value.map((cell) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: pw.Text(
                cell,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
