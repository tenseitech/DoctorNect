import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/session/lab_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../patient/lab/models/lab_models.dart';
import '../data/lab_worklist_store.dart';
import 'package:medibond/features/shared/widgets/lab_page_layout.dart';
import '../widgets/lab_report_upload_sheet.dart';
import 'lab_dashboard_tabs.dart';
import '../../../core/theme/app_typography.dart';

enum _PatientTypeFilter { all, walkIn, home, reportPending }

class LabAllPatientsScreen extends StatefulWidget {
  const LabAllPatientsScreen({super.key});

  @override
  State<LabAllPatientsScreen> createState() => _LabAllPatientsScreenState();
}

class _LabAllPatientsScreenState extends State<LabAllPatientsScreen> {
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('dd MMM yyyy');

  _PatientTypeFilter _typeFilter = _PatientTypeFilter.all;
  DateTime? _selectedDate;
  bool _refreshing = false;

  static const _labPurple = AppColors.labPurple;
  static const _lineColor = Color(0xFFE2E8F0);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<LabBookingRecord> _bookingsForLab() {
    final labId = LabSession.loggedInLabId;
    return LabWorklistStore.instance.bookings
        .where((b) => b.labId == labId)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  bool _needsReport(LabBookingRecord booking) =>
      !booking.hasReport &&
      booking.status != 'declined' &&
      booking.status != 'requested';

  List<LabBookingRecord> _applyFilters(List<LabBookingRecord> bookings) {
    var list = bookings;

    list = switch (_typeFilter) {
      _PatientTypeFilter.all => list,
      _PatientTypeFilter.walkIn => list
          .where((b) => b.collectionType == LabCollectionType.walkIn.name)
          .toList(),
      _PatientTypeFilter.home => list
          .where((b) => b.collectionType == LabCollectionType.home.name)
          .toList(),
      _PatientTypeFilter.reportPending => list.where(_needsReport).toList(),
    };

    final date = _selectedDate;
    if (date != null) {
      list = list.where((b) => _isSameDay(b.dateTime, date)).toList();
    }

    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (b) =>
                b.patientName.toLowerCase().contains(q) ||
                b.displayTestName.toLowerCase().contains(q),
          )
          .toList();
    }

    return list;
  }

  Future<void> _refresh() async {
    final labId = LabSession.loggedInLabId;
    if (labId.isEmpty) return;

    setState(() => _refreshing = true);
    try {
      final bookings =
          await FirestoreService.instance.labBooking.fetchForLab(labId);
      LabWorklistStore.instance.mergeBookings(bookings);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
              Theme.of(context).colorScheme.copyWith(primary: _labPurple),
        ),
        child: child!,
      ),
    );
    if (picked != null)
      setState(() =>
          _selectedDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _uploadReport(LabBookingRecord booking) async {
    await LabReportUploadSheet.show(context, booking: booking);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        title: Text('All Patients',
            style: GoogleFonts.inter(
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.surfaceOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _lineColor),
        ),
      ),
      body: ListenableBuilder(
        listenable: LabWorklistStore.instance,
        builder: (context, _) {
          final all = _bookingsForLab();
          final patients = _applyFilters(all);
          final pendingReports = all.where(_needsReport).length;

          return LabPageLayout(
            maxWidth: 960,
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: _labPurple,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text(
                    'Patient bookings',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${all.length} total · ${patients.length} shown${pendingReports > 0 ? ' · $pendingReports need report' : ''}',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search patient or test...',
                      hintStyle: GoogleFonts.inter(
                          fontSize: AppTypography.bodySmall,
                          color: AppColors.textSecondaryOf(context)),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: AppColors.surfaceOf(context),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _lineColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _lineColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _labPurple, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DateFilterRow(
                    selectedDate: _selectedDate,
                    dateFormat: _dateFormat,
                    onPickDate: _pickDate,
                    onClearDate: () => setState(() => _selectedDate = null),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in [
                        (_PatientTypeFilter.all, 'All'),
                        (_PatientTypeFilter.walkIn, 'Walk-in'),
                        (_PatientTypeFilter.home, 'Home'),
                        (_PatientTypeFilter.reportPending, 'Report pending'),
                      ])
                        FilterChip(
                          label: Text(entry.$2),
                          selected: _typeFilter == entry.$1,
                          onSelected: (_) =>
                              setState(() => _typeFilter = entry.$1),
                          selectedColor: _labPurple.withValues(alpha: 0.14),
                          checkmarkColor: _labPurple,
                          labelStyle: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            fontWeight: FontWeight.w600,
                            color: _typeFilter == entry.$1
                                ? _labPurple
                                : AppColors.textSecondaryOf(context),
                          ),
                          side: BorderSide(
                            color: _typeFilter == entry.$1
                                ? _labPurple
                                : _lineColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_refreshing && patients.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                          child: CircularProgressIndicator(color: _labPurple)),
                    )
                  else if (patients.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          all.isEmpty
                              ? 'No patient bookings yet. Walk-ins and app bookings will appear here.'
                              : 'No patients match your filters.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              color: AppColors.textSecondaryOf(context),
                              height: 1.4),
                        ),
                      ),
                    )
                  else
                    ...patients.map((booking) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PatientBookingCard(
                            booking: booking,
                            needsReport: _needsReport(booking),
                            onUploadReport: () => _uploadReport(booking),
                          ),
                        )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DateFilterRow extends StatelessWidget {
  const _DateFilterRow({
    required this.selectedDate,
    required this.dateFormat,
    required this.onPickDate,
    required this.onClearDate,
  });

  final DateTime? selectedDate;
  final DateFormat dateFormat;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;

  @override
  Widget build(BuildContext context) {
    final label =
        selectedDate == null ? 'All dates' : dateFormat.format(selectedDate!);

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onPickDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 18, color: AppColors.textSecondaryOf(context)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.bodySmall,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down,
                      color: AppColors.textSecondaryOf(context)),
                ],
              ),
            ),
          ),
        ),
        if (selectedDate != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: onClearDate,
            style: TextButton.styleFrom(foregroundColor: AppColors.labPurple),
            child: Text('Clear',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: AppTypography.bodySmall)),
          ),
        ],
      ],
    );
  }
}

class _PatientBookingCard extends StatelessWidget {
  const _PatientBookingCard({
    required this.booking,
    required this.needsReport,
    required this.onUploadReport,
  });

  final LabBookingRecord booking;
  final bool needsReport;
  final VoidCallback onUploadReport;

  @override
  Widget build(BuildContext context) {
    final isWalkIn = booking.collectionType == LabCollectionType.walkIn.name;
    final statusColor = labOrderStatusColor(booking.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.labPurple.withValues(alpha: 0.12),
                child: Text(
                  booking.patientName.trim().isNotEmpty
                      ? booking.patientName.trim()[0].toUpperCase()
                      : 'P',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, color: AppColors.labPurple),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.patientName,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isWalkIn ? 'Walk-in' : 'Home collection',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                initialValue: booking.status,
                onSelected: (newStatus) {
                  if (newStatus != booking.status) {
                    // Update all linked booking docs for grouped bookings
                    for (final id in booking.linkedBookingIds) {
                      FirestoreService.instance.labBooking
                          .updateBookingStatus(id, newStatus);
                    }
                    LabWorklistStore.instance
                        .updateBookingStatusLocal(booking.bookingId, newStatus);
                  }
                },
                tooltip: 'Update Status',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        labOrderStatusLabel(booking.status),
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: statusColor),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 14, color: statusColor),
                    ],
                  ),
                ),
                itemBuilder: (context) => [
                  'requested',
                  'confirmed',
                  'processing',
                  'completed',
                  'declined',
                ]
                    .map((status) => PopupMenuItem<String>(
                          value: status,
                          child: Text(labOrderStatusLabel(status)),
                        ))
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: booking.allTestNames
                .map((testName) => Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: 5, right: 6),
                            child: Icon(Icons.circle,
                                size: 4,
                                color: AppColors.textSecondaryOf(context)),
                          ),
                          Expanded(
                            child: Text(
                              testName,
                              style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodySmall,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          Text(
            '${DateFormat('dd MMM yyyy').format(booking.dateTime)} · ${booking.slotLabel}',
            style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                color: AppColors.textSecondaryOf(context)),
          ),
          if (!isWalkIn && booking.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              booking.address,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  color: AppColors.textSecondaryOf(context)),
            ),
          ],
          if (booking.hasReport) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 15, color: AppColors.pharmacyGreen),
                const SizedBox(width: 6),
                Text(
                  'Report sent',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      color: AppColors.pharmacyGreen,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ] else if (needsReport) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onUploadReport,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Share report'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.labPurple,
                minimumSize: const Size(double.infinity, 42),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
