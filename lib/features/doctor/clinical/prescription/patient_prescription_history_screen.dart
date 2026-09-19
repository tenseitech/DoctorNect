import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../patients/data/doctor_patients_service.dart';
import '../data/clinical_prescription_store.dart';
import '../models/clinical_models.dart';
import '../../widgets/patient_sharing_blocked_notice.dart';
import 'edit_prescription_screen.dart';
import 'prescription_preview_modal.dart';
import '../../../../core/theme/app_typography.dart';

class PatientPrescriptionHistoryScreen extends StatefulWidget {
  const PatientPrescriptionHistoryScreen({
    super.key,
    required this.patient,
  });

  final PatientClinicalContext patient;

  @override
  State<PatientPrescriptionHistoryScreen> createState() =>
      _PatientPrescriptionHistoryScreenState();
}

class _PatientPrescriptionHistoryScreenState extends State<PatientPrescriptionHistoryScreen> {
  bool? _clinicalDataBlocked;

  String get _patientId =>
      widget.patient.patientId ??
      'PAT-${widget.patient.patientName.hashCode.abs().toString().padLeft(6, '0')}';

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    final blocked = !await DoctorPatientsService.canViewClinicalHistoryForKey(_patientId);
    if (!blocked) {
      await ClinicalPrescriptionStore.instance.refreshForPatient(
        _patientId,
        preferCache: true,
      );
    }
    if (!mounted) return;
    setState(() => _clinicalDataBlocked = blocked);
  }

  @override
  Widget build(BuildContext context) {
    if (_clinicalDataBlocked == null) {
      return Scaffold(
        backgroundColor: AppColors.cardBgOf(context),
        appBar: AppBar(
          title: Text(
            'Prescription History',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.headlineSmall),
          ),
          backgroundColor: AppColors.surfaceOf(context),
          foregroundColor: AppColors.textPrimaryOf(context),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_clinicalDataBlocked!) {
      return Scaffold(
        backgroundColor: AppColors.cardBgOf(context),
        appBar: AppBar(
          title: Text(
            'Prescription History',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.headlineSmall),
          ),
          backgroundColor: AppColors.surfaceOf(context),
          foregroundColor: AppColors.textPrimaryOf(context),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: const PatientSharingBlockedEmptyState(),
      );
    }

    final patientId = _patientId;
    final hPad = ResponsiveLayout.isCompact(context) ? 12.0 : 20.0;
    final compact = ResponsiveLayout.isCompact(context);
    final screenW = ResponsiveLayout.screenWidth(context);
    final tableMaxWidth = compact ? screenW - (hPad * 2) : (screenW * 0.82).clamp(640.0, 880.0);

    return ListenableBuilder(
      listenable: ClinicalPrescriptionStore.instance,
      builder: (context, _) {
        final records = ClinicalPrescriptionStore.instance.forPatient(patientId);

        return Scaffold(
          backgroundColor: AppColors.cardBgOf(context),
          appBar: AppBar(
            title: Text(
              'Prescription History',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.headlineSmall),
            ),
            backgroundColor: AppColors.surfaceOf(context),
            foregroundColor: AppColors.textPrimaryOf(context),
            elevation: 0,
            surfaceTintColor: Colors.transparent,
          ),
          body: records.isEmpty
              ? const _EmptyHistoryState()
              : ListView(
                  padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: tableMaxWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${records.length} visit${records.length == 1 ? '' : 's'}',
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.bodySmall,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _HistoryTable(records: records, compact: compact, patient: widget.patient),
                            if (ClinicalPrescriptionStore.instance.hasMorePatient) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.center,
                                child: OutlinedButton(
                                  onPressed: () => ClinicalPrescriptionStore.instance.loadMoreForPatient(
                                    patientId,
                                    preferCache: false,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.doctorBlue,
                                    side: BorderSide(color: AppColors.doctorBlue.withValues(alpha: 0.5)),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  ),
                                  child: Text(
                                    'Load older prescriptions',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.bodySmall),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.45)),
            const SizedBox(height: 12),
            Text(
              'No saved prescriptions yet',
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyLarge,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Prescriptions saved to EMR for this patient will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({
    required this.records,
    required this.compact,
    required this.patient,
  });

  final List<PrescriptionDraft> records;
  final bool compact;
  final PatientClinicalContext patient;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.75)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _HistoryTableHeader(compact: compact),
          for (var i = 0; i < records.length; i++) ...[
            Divider(height: 1, color: AppColors.borderOf(context).withValues(alpha: 0.6)),
            _HistoryTableRow(
              draft: records[i],
              compact: compact,
              patient: patient,
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryTableHeader extends StatelessWidget {
  const _HistoryTableHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.cardBgOf(context),
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: compact ? 3 : 2,
            child: Text(
              compact ? 'Date & time' : 'DATE & TIME',
              style: _headerStyle(context, compact),
            ),
          ),
          Expanded(
            flex: compact ? 3 : 2,
            child: Text('DX', style: _headerStyle(context, compact)),
          ),
          Expanded(
            flex: compact ? 5 : 4,
            child: Text(
              compact ? 'Prescription' : 'PRESCRIPTION',
              style: _headerStyle(context, compact),
            ),
          ),
          SizedBox(
            width: compact ? 108 : 120,
            child: Text(
              'ACTIONS',
              textAlign: TextAlign.end,
              style: _headerStyle(context, compact),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _headerStyle(BuildContext context, bool compact) => GoogleFonts.inter(
        fontSize: compact ? 10 : 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: AppColors.textSecondaryOf(context),
      );
}

class _HistoryTableRow extends StatelessWidget {
  const _HistoryTableRow({
    required this.draft,
    required this.compact,
    required this.patient,
  });

  final PrescriptionDraft draft;
  final bool compact;
  final PatientClinicalContext patient;

  static String _prescriptionSummary(PrescriptionDraft draft) {
    final meds = draft.validMedicines;
    if (meds.isEmpty) return '—';

    final labels = meds.map((m) {
      final name = m.name.trim();
      final dosage = m.dosageLabel.trim();
      return dosage.isEmpty ? name : '$name $dosage';
    }).where((s) => s.isNotEmpty);

    final list = labels.toList();
    if (list.length <= 2) return list.join(', ');

    return '${list.take(2).join(', ')} · +${list.length - 2} more';
  }

  @override
  Widget build(BuildContext context) {
    final when = draft.prescriptionDate;
    final date = DateFormat('dd MMM yyyy').format(when);
    final time = DateFormat('hh:mm a').format(when);
    final dx = draft.primaryDiagnosis.trim();
    final rx = _prescriptionSummary(draft);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: compact ? 3 : 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: GoogleFonts.inter(
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: GoogleFonts.inter(
                    fontSize: compact ? 11 : 12,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: compact ? 3 : 2,
            child: Text(
              dx.isEmpty ? '—' : dx,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 12 : 13,
                color: AppColors.textPrimaryOf(context),
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            flex: compact ? 5 : 4,
            child: Text(
              rx,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 12 : 13,
                color: AppColors.textPrimaryOf(context),
                height: 1.35,
              ),
            ),
          ),
          SizedBox(
            width: compact ? 108 : 120,
            child: Align(
              alignment: Alignment.topRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => EditPrescriptionScreen.open(
                      context,
                      patient: patient,
                      draft: draft,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.doctorBlue,
                      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: GoogleFonts.inter(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    onPressed: () => PrescriptionPreviewModal.show(context, draft: draft),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.doctorBlue,
                      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: GoogleFonts.inter(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Preview'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
