import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../doctor/models/doctor_models.dart';
import '../data/doctor_profile_store.dart';
import '../../patients/data/doctor_patients_service.dart';
import '../../../../core/theme/app_typography.dart';

enum _Period { weekly, monthly, yearly, custom }

enum _CardFilter { all, newVisit, followUp }

class PatientDataSection extends StatefulWidget {
  const PatientDataSection({super.key});

  @override
  State<PatientDataSection> createState() => _PatientDataSectionState();
}

class _PatientDataSectionState extends State<PatientDataSection> {
  _Period _period = _Period.monthly;
  _CardFilter _cardFilter = _CardFilter.all;
  DateTimeRange? _customRange;
  Set<String> _blockedPatientKeys = {};
  int _sharingLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    SharedAppointmentsStore.instance.addListener(_onAppointmentsChanged);
    unawaited(_refreshSharingBlocks());
  }

  @override
  void dispose() {
    SharedAppointmentsStore.instance.removeListener(_onAppointmentsChanged);
    super.dispose();
  }

  void _onAppointmentsChanged() {
    if (mounted) setState(() {});
    unawaited(_refreshSharingBlocks());
  }

  Future<void> _refreshSharingBlocks() async {
    final generation = ++_sharingLoadGeneration;
    final blocked = <String>{};
    final seen = <String>{};

    for (final record in _allRecords) {
      final key = DoctorPatientsService.patientGroupKey(record);
      if (!seen.add(key)) continue;
      if (!await DoctorPatientsService.canViewClinicalHistoryForKey(key)) {
        blocked.add(key);
      }
    }

    if (!mounted || generation != _sharingLoadGeneration) return;
    setState(() => _blockedPatientKeys = blocked);
  }

  bool _clinicalDataBlockedFor(DoctorNectAppointmentRecord record) {
    return _blockedPatientKeys
        .contains(DoctorPatientsService.patientGroupKey(record));
  }

  Future<Map<String, bool>> _clinicalSharingByPatientKey(
    Iterable<DoctorNectAppointmentRecord> records,
  ) async {
    final sharing = <String, bool>{};
    for (final record in records) {
      final key = DoctorPatientsService.patientGroupKey(record);
      sharing[key] ??=
          await DoctorPatientsService.canViewClinicalHistoryForKey(key);
    }
    return sharing;
  }

  List<DoctorNectAppointmentRecord> get _allRecords {
    final doctorId = DoctorSession.loggedInDoctorId;
    return SharedAppointmentsStore.instance.records
        .where((r) => r.doctorId == doctorId && !r.isCancelled)
        .toList();
  }

  List<DoctorNectAppointmentRecord> get _filtered {
    final now = DateTime.now();
    if (_period == _Period.custom && _customRange != null) {
      final start = _customRange!.start;
      final end = _customRange!.end.add(const Duration(days: 1));
      return _allRecords
          .where((r) => r.dateTime.isAfter(start) && r.dateTime.isBefore(end))
          .toList()
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    }
    DateTime cutoff;
    switch (_period) {
      case _Period.weekly:
        cutoff = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 7));
      case _Period.monthly:
        cutoff = DateTime(now.year, now.month, 1);
      case _Period.yearly:
        cutoff = DateTime(now.year, 1, 1);
      case _Period.custom:
        cutoff = DateTime(now.year, 1, 1);
    }
    return _allRecords.where((r) => r.dateTime.isAfter(cutoff)).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  List<DoctorNectAppointmentRecord> get _displayRecords {
    final base = _filtered;
    switch (_cardFilter) {
      case _CardFilter.all:
        return base;
      case _CardFilter.newVisit:
        return base
            .where((r) => r.visitType == AppointmentType.newVisit)
            .toList();
      case _CardFilter.followUp:
        return base
            .where((r) => r.visitType == AppointmentType.followUp)
            .toList();
    }
  }

  // ── PDF export ──────────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    final records = _filtered;
    final sharing = await _clinicalSharingByPatientKey(records);
    final doctorName = DoctorProfileStore.displayName;
    final periodLabel = switch (_period) {
      _Period.weekly => 'Weekly',
      _Period.monthly => 'Monthly',
      _Period.yearly => 'Yearly',
      _Period.custom => 'Custom',
    };
    final now = DateTime.now();
    final dateRange = _dateRangeLabel();
    final df = DateFormat('dd MMM yyyy');
    final tf = DateFormat('hh:mm a');

    final pdf = pw.Document();

    // Unique patients set
    final uniquePatients = <String>{};
    for (final r in records) {
      final key = DoctorPatientsService.patientGroupKey(r);
      uniquePatients.add(key);
    }

    final newVisits =
        records.where((r) => r.visitType == AppointmentType.newVisit).length;
    final followUps =
        records.where((r) => r.visitType == AppointmentType.followUp).length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Patient Data Report',
                      style: pw.TextStyle(
                        fontSize: AppTypography.headlineMedium,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.teal800,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Dr. $doctorName',
                      style: pw.TextStyle(
                          fontSize: AppTypography.bodySmall,
                          color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '$periodLabel Report',
                      style: pw.TextStyle(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.teal700,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      dateRange,
                      style:
                          pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                    pw.Text(
                      'Generated: ${df.format(now)}',
                      style:
                          pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(color: PdfColors.teal200, thickness: 1.5),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (ctx) => [
          // Summary stats — first page only (header repeats on every page)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _pdfStatBox('Total Patients', '${uniquePatients.length}'),
              _pdfStatBox('Total Visits', '${records.length}'),
              _pdfStatBox('New Visits', '$newVisits'),
              _pdfStatBox('Follow-ups', '$followUps'),
            ],
          ),
          pw.SizedBox(height: 12),
          if (records.isEmpty)
            pw.Center(
              child: pw.Padding(
                padding: const pw.EdgeInsets.all(40),
                child: pw.Text(
                  'No patient records found for this period.',
                  style: pw.TextStyle(color: PdfColors.grey600),
                ),
              ),
            )
          else ...[
            // Table header
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(0.7),
                3: const pw.FlexColumnWidth(0.8),
                4: const pw.FlexColumnWidth(1.5),
                5: const pw.FlexColumnWidth(1.2),
                6: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                  children: [
                    _pdfHeaderCell('#'),
                    _pdfHeaderCell('Patient Name'),
                    _pdfHeaderCell('Age'),
                    _pdfHeaderCell('Gender'),
                    _pdfHeaderCell('Date & Time'),
                    _pdfHeaderCell('Visit Type'),
                    _pdfHeaderCell('Diagnosis'),
                  ],
                ),
                ...records.asMap().entries.map((entry) {
                  final i = entry.key;
                  final r = entry.value;
                  final isEven = i.isEven;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: isEven ? PdfColors.grey50 : PdfColors.white,
                    ),
                    children: [
                      _pdfCell('${i + 1}', center: true),
                      _pdfCell(r.patientName),
                      _pdfCell('${r.patientAge}', center: true),
                      _pdfCell(AppConstants.patientGenderLabel(r.patientGender),
                          center: true),
                      _pdfCell(
                          '${df.format(r.dateTime)}\n${tf.format(r.dateTime)}'),
                      _pdfCell(
                        r.visitType == AppointmentType.followUp
                            ? 'Follow-up'
                            : 'New Visit',
                        center: true,
                      ),
                      _pdfCell(
                        sharing[DoctorPatientsService.patientGroupKey(r)] ==
                                true
                            ? (r.diagnosis ?? '-')
                            : '—',
                      ),
                    ],
                  );
                }),
              ],
            ),
          ],
        ],
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'DoctorNect - Confidential Medical Records',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name:
          'patient_data_${periodLabel.toLowerCase()}_${DateFormat('yyyyMMdd').format(now)}.pdf',
    );
  }

  pw.Widget _pdfStatBox(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.teal50,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.teal200),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: AppTypography.headlineSmall,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.teal800,
            ),
          ),
          pw.Text(label,
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  pw.Widget _pdfHeaderCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _pdfCell(String text, {bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey900),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  String _dateRangeLabel() {
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');
    if (_period == _Period.custom) {
      if (_customRange != null) {
        return '${df.format(_customRange!.start)} to ${df.format(_customRange!.end)}';
      }
      return 'Select date range';
    }
    DateTime from;
    switch (_period) {
      case _Period.weekly:
        from = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 7));
      case _Period.monthly:
        from = DateTime(now.year, now.month, 1);
      case _Period.yearly:
        from = DateTime(now.year, 1, 1);
      case _Period.custom:
        from = now;
    }
    return '${df.format(from)} to ${df.format(now)}';
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1);
    final initial = _customRange ??
        DateTimeRange(
          start: yearStart,
          end: now,
        );
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (ctx) => _CustomRangeDialog(
        initial: initial,
        firstDate: yearStart,
        lastDate: now,
      ),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _cardFilter = _CardFilter.all;
      });
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Data'),
        actions: [
          TextButton.icon(
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
            label: const Text('Export PDF'),
            style: TextButton.styleFrom(foregroundColor: AppColors.practoTeal),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: SharedAppointmentsStore.instance,
        builder: (context, _) {
          final records = _filtered;
          final displayRecords = _displayRecords;
          final total = _allRecords.length;
          final newVisits = records
              .where((r) => r.visitType == AppointmentType.newVisit)
              .length;
          final followUps = records
              .where((r) => r.visitType == AppointmentType.followUp)
              .length;

          return Column(
            children: [
              // Period selector
              _PeriodSelector(
                selected: _period,
                onChanged: (p) async {
                  if (p == _Period.custom) {
                    setState(() => _period = p);
                    await _pickCustomRange();
                  } else {
                    setState(() {
                      _period = p;
                      _customRange = null;
                      _cardFilter = _CardFilter.all;
                    });
                  }
                },
              ),

              // Date range label
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      _dateRangeLabel(),
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (_period == _Period.custom) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _pickCustomRange,
                        child: Text(
                          'Change',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.practoTeal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Stats cards
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    _StatCard(
                      label: 'Total Visits',
                      value: '${records.length}',
                      icon: Icons.calendar_today_outlined,
                      color: Colors.blue[700]!,
                      isActive: _cardFilter == _CardFilter.all,
                      onTap: () =>
                          setState(() => _cardFilter = _CardFilter.all),
                    ),
                    const SizedBox(width: 8),
                    _StatCard(
                      label: 'New Visits',
                      value: '$newVisits',
                      icon: Icons.fiber_new_outlined,
                      color: Colors.green[700]!,
                      isActive: _cardFilter == _CardFilter.newVisit,
                      onTap: () => setState(() => _cardFilter =
                          _cardFilter == _CardFilter.newVisit
                              ? _CardFilter.all
                              : _CardFilter.newVisit),
                    ),
                    const SizedBox(width: 8),
                    _StatCard(
                      label: 'Follow-ups',
                      value: '$followUps',
                      icon: Icons.repeat_outlined,
                      color: Colors.orange[700]!,
                      isActive: _cardFilter == _CardFilter.followUp,
                      onTap: () => setState(() => _cardFilter =
                          _cardFilter == _CardFilter.followUp
                              ? _CardFilter.all
                              : _CardFilter.followUp),
                    ),
                  ],
                ),
              ),

              // Total all-time count banner
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.practoTeal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.practoTeal.withValues(alpha: 0.18)),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.bar_chart_rounded,
                          color: AppColors.practoTeal, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'All-time total visits: ',
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            color: Colors.grey[700]),
                      ),
                      Text(
                        '$total',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w700,
                          color: AppColors.practoTeal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1),

              // Active filter label
              if (_cardFilter != _CardFilter.all)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Icon(Icons.filter_list_rounded,
                          size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Text(
                        'Showing: ${switch (_cardFilter) {
                          _CardFilter.newVisit => 'New Visits',
                          _CardFilter.followUp => 'Follow-ups',
                          _CardFilter.all => '',
                        }} (${displayRecords.length})',
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: Colors.grey[600]),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _cardFilter = _CardFilter.all),
                        child: Text(
                          'Clear',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.practoTeal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Patient list
              Expanded(
                child: displayRecords.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline,
                                size: 52, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              'No patient records for this filter',
                              style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodyMedium,
                                  color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: displayRecords.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) => _PatientRow(
                              record: displayRecords[i],
                              index: i,
                              hideClinicalData:
                                  _clinicalDataBlockedFor(displayRecords[i]),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Period selector tabs ──────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onChanged});

  final _Period selected;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: _Period.values.map((p) {
            final label = switch (p) {
              _Period.weekly => 'Weekly',
              _Period.monthly => 'Monthly',
              _Period.yearly => 'Yearly',
              _Period.custom => 'Custom',
            };
            final icon = p == _Period.custom ? Icons.date_range_outlined : null;
            final isActive = p == selected;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.practoTeal : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon,
                            size: 13,
                            color: isActive
                                ? AppColors.surfaceOf(context)
                                : Colors.grey[600]),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w500,
                          color: isActive
                              ? AppColors.surfaceOf(context)
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.18)
                : color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? color : color.withValues(alpha: 0.18),
              width: isActive ? 1.8 : 1.0,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.18), blurRadius: 6)
                  ]
                : [],
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                label,
                style:
                    GoogleFonts.inter(fontSize: 9.5, color: Colors.grey[600]),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Patient row ───────────────────────────────────────────────────────────────

class _PatientRow extends StatelessWidget {
  const _PatientRow({
    required this.record,
    required this.index,
    required this.hideClinicalData,
  });

  final DoctorNectAppointmentRecord record;
  final int index;
  final bool hideClinicalData;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    final tf = DateFormat('hh:mm a');
    final isFollowUp = record.visitType == AppointmentType.followUp;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Serial number
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}.',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium, color: Colors.grey[500]),
            ),
          ),
          // Avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.practoTeal.withValues(alpha: 0.12),
            child: Text(
              record.patientName.isNotEmpty
                  ? record.patientName[0].toUpperCase()
                  : '?',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w600,
                  color: AppColors.practoTeal),
            ),
          ),
          const SizedBox(width: 10),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.patientName,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isFollowUp
                            ? Colors.orange.withValues(alpha: 0.12)
                            : Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isFollowUp ? 'Follow-up' : 'New Visit',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isFollowUp
                              ? Colors.orange[800]
                              : Colors.green[800],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${record.patientAge} yrs · ${AppConstants.patientGenderLabel(record.patientGender)}',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 11, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '${df.format(record.dateTime)}  ${tf.format(record.dateTime)}',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          color: Colors.grey[500]),
                    ),
                  ],
                ),
                if (!hideClinicalData &&
                    record.diagnosis != null &&
                    record.diagnosis!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.medical_information_outlined,
                          size: 11, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          record.diagnosis!,
                          style: GoogleFonts.inter(
                              fontSize: AppTypography.labelSmall,
                              color: Colors.grey[500]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Custom date range dialog ──────────────────────────────────────────────────

class _CustomRangeDialog extends StatefulWidget {
  const _CustomRangeDialog({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTimeRange initial;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_CustomRangeDialog> createState() => _CustomRangeDialogState();
}

class _CustomRangeDialogState extends State<_CustomRangeDialog> {
  late DateTime _start;
  late DateTime _end;
  bool _pickingStart = true;

  @override
  void initState() {
    super.initState();
    _start = widget.initial.start;
    _end = widget.initial.end;
  }

  String _fmt(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              decoration: BoxDecoration(
                color: AppColors.practoTeal,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Icon(Icons.date_range_outlined,
                      color: AppColors.surfaceOf(context), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Select Date Range',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyLarge,
                      fontWeight: FontWeight.w600,
                      color: AppColors.surfaceOf(context),
                    ),
                  ),
                ],
              ),
            ),

            // Start / End chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _DateChip(
                      label: 'From',
                      date: _fmt(_start),
                      isActive: _pickingStart,
                      onTap: () => setState(() => _pickingStart = true),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward,
                        size: 16, color: Colors.grey[400]),
                  ),
                  Expanded(
                    child: _DateChip(
                      label: 'To',
                      date: _fmt(_end),
                      isActive: !_pickingStart,
                      onTap: () => setState(() => _pickingStart = false),
                    ),
                  ),
                ],
              ),
            ),

            // Inline range calendar
            _RangeCalendar(
              start: _start,
              end: _end,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              pickingStart: _pickingStart,
              onDateTapped: (picked) {
                setState(() {
                  if (_pickingStart) {
                    _start = picked;
                    if (_start.isAfter(_end)) _end = _start;
                    _pickingStart = false;
                  } else {
                    if (picked.isBefore(_start)) {
                      _end = _start;
                      _start = picked;
                    } else {
                      _end = picked;
                    }
                    _pickingStart = true;
                  }
                });
              },
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: GoogleFonts.inter(color: Colors.grey[600])),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.practoTeal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(90, 40),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.pop(
                      context,
                      DateTimeRange(start: _start, end: _end),
                    ),
                    child: Text('Apply',
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Range-highlighting calendar ───────────────────────────────────────────────

class _RangeCalendar extends StatefulWidget {
  const _RangeCalendar({
    required this.start,
    required this.end,
    required this.firstDate,
    required this.lastDate,
    required this.pickingStart,
    required this.onDateTapped,
  });

  final DateTime start;
  final DateTime end;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool pickingStart;
  final ValueChanged<DateTime> onDateTapped;

  @override
  State<_RangeCalendar> createState() => _RangeCalendarState();
}

class _RangeCalendarState extends State<_RangeCalendar> {
  late DateTime _viewMonth;

  @override
  void initState() {
    super.initState();
    // Open on current month (same year as yearly filter default)
    _viewMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
  }

  void _prevMonth() {
    final prev = DateTime(_viewMonth.year, _viewMonth.month - 1);
    if (!prev
        .isBefore(DateTime(widget.firstDate.year, widget.firstDate.month))) {
      setState(() => _viewMonth = prev);
    }
  }

  void _nextMonth() {
    final next = DateTime(_viewMonth.year, _viewMonth.month + 1);
    if (!next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month))) {
      setState(() => _viewMonth = next);
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime d) =>
      d.isAfter(widget.start.subtract(const Duration(days: 1))) &&
      d.isBefore(widget.end.add(const Duration(days: 1)));

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_viewMonth);
    final daysInMonth =
        DateUtils.getDaysInMonth(_viewMonth.year, _viewMonth.month);
    final firstWeekday =
        DateTime(_viewMonth.year, _viewMonth.month, 1).weekday % 7;
    final canGoPrev = !DateTime(_viewMonth.year, _viewMonth.month - 1)
        .isBefore(DateTime(widget.firstDate.year, widget.firstDate.month));
    final canGoNext = !DateTime(_viewMonth.year, _viewMonth.month + 1)
        .isAfter(DateTime(widget.lastDate.year, widget.lastDate.month));

    const weekDays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          // Month nav
          Row(
            children: [
              IconButton(
                onPressed: canGoPrev ? _prevMonth : null,
                icon: const Icon(Icons.chevron_left),
                splashRadius: 18,
                iconSize: 20,
                color: Colors.grey[700],
              ),
              Expanded(
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: canGoNext ? _nextMonth : null,
                icon: const Icon(Icons.chevron_right),
                splashRadius: 18,
                iconSize: 20,
                color: Colors.grey[700],
              ),
            ],
          ),
          // Week day headers
          Row(
            children: weekDays
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          // Day grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: firstWeekday + daysInMonth,
            itemBuilder: (_, index) {
              if (index < firstWeekday) return const SizedBox.shrink();
              final day = index - firstWeekday + 1;
              final date = DateTime(_viewMonth.year, _viewMonth.month, day);
              final isStart = _isSameDay(date, widget.start);
              final isEnd = _isSameDay(date, widget.end);
              final inRange = _inRange(date);
              final isEndpoint = isStart || isEnd;
              final isFuture = date.isAfter(widget.lastDate);
              final isPast = date.isBefore(widget.firstDate);
              final disabled = isFuture || isPast;

              // Range strip: left half, right half, or full
              final isFirst = day == 1 || date.weekday % 7 == 0;
              final isLast = day == daysInMonth || (date.weekday % 7) == 6;

              return GestureDetector(
                onTap: disabled ? null : () => widget.onDateTapped(date),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Range background strip
                    if (inRange && !isStart && !isEnd)
                      Positioned.fill(
                        child: Container(
                          color: AppColors.practoTeal.withValues(alpha: 0.12),
                        ),
                      ),
                    // Start: right half strip
                    if (isStart && !_isSameDay(widget.start, widget.end))
                      Positioned(
                        left: isFirst ? 0 : 16,
                        right: 0,
                        top: 4,
                        bottom: 4,
                        child: Container(
                            color:
                                AppColors.practoTeal.withValues(alpha: 0.12)),
                      ),
                    // End: left half strip
                    if (isEnd && !_isSameDay(widget.start, widget.end))
                      Positioned(
                        left: 0,
                        right: isLast ? 0 : 16,
                        top: 4,
                        bottom: 4,
                        child: Container(
                            color:
                                AppColors.practoTeal.withValues(alpha: 0.12)),
                      ),
                    // Endpoint circle
                    if (isEndpoint)
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.practoTeal,
                          shape: BoxShape.circle,
                        ),
                      ),
                    // Day text
                    Text(
                      '$day',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        fontWeight:
                            isEndpoint ? FontWeight.w700 : FontWeight.w400,
                        color: isEndpoint
                            ? Colors.white
                            : disabled
                                ? Colors.grey[300]
                                : inRange
                                    ? AppColors.practoTeal
                                    : Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.date,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final String date;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.practoTeal.withValues(alpha: 0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.practoTeal : Colors.grey[300]!,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: isActive ? AppColors.practoTeal : Colors.grey[500],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              date,
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                fontWeight: FontWeight.w600,
                color: isActive ? AppColors.practoTeal : Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
