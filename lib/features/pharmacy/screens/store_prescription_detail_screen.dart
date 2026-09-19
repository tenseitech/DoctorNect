import '../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../doctor/clinical/prescription/prescription_preview_modal.dart';
import '../data/pharmacy_prescription_store.dart';
import '../models/pharmacy_models.dart';
import '../../../core/theme/app_typography.dart';

const _detailContentMaxWidth = 960.0;
const _lineColor = Color(0xFFE2E8F0);
const _headerBg = Color(0xFFF1F5F9);

String _pharmacyDoctorLabel(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Doctor';
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('dr.') || lower.startsWith('dr ')) return trimmed;
  return 'Dr. $trimmed';
}

class StorePrescriptionDetailScreen extends StatefulWidget {
  const StorePrescriptionDetailScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  State<StorePrescriptionDetailScreen> createState() =>
      _StorePrescriptionDetailScreenState();
}

class _StorePrescriptionDetailScreenState
    extends State<StorePrescriptionDetailScreen> {
  final _notesController = TextEditingController();

  PharmacyPrescriptionDelivery? get _delivery =>
      PharmacyPrescriptionStore.instance.findById(widget.deliveryId);

  @override
  void initState() {
    super.initState();
    final d = _delivery;
    if (d != null) {
      _notesController.text = d.dispensingNotes;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final d2 = _delivery;
      if (d2 != null && d2.status == PharmacyDeliveryStatus.sent) {
        PharmacyPrescriptionStore.instance.markViewed(d2.id);
      }
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _markDispensed(PharmacyPrescriptionDelivery delivery) async {
    final hasPending = delivery.medicineLines
        .any((l) => l.availability == MedicineAvailability.pending);
    if (hasPending) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some medicines not reviewed'),
          content: const Text(
            'One or more medicines are still marked as pending. Mark as dispensed anyway?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Dispense anyway')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    try {
      await PharmacyPrescriptionStore.instance.markDispensed(
        delivery.id,
        notes: _notesController.text.trim(),
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context, 'Failed to mark as dispensed. Please retry.');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PharmacyPrescriptionStore.instance,
      builder: (context, _) {
        final delivery = _delivery;
        if (delivery == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Prescription')),
            body: const Center(child: Text('Prescription not found')),
          );
        }

        final draft = delivery.draft;
        final isDispensed =
            delivery.status == PharmacyDeliveryStatus.dispensed ||
                delivery.status == PharmacyDeliveryStatus.partiallyDispensed;
        final reviewed = delivery.medicineLines
            .where((l) => l.availability != MedicineAvailability.pending)
            .length;

        return Scaffold(
          backgroundColor: AppColors.surfaceOf(context),
          appBar: AppBar(
            title: Text(draft.prescriptionId,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyLarge,
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
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: _detailContentMaxWidth),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        _PrescriptionHeader(
                          delivery: delivery,
                          reviewedCount: reviewed,
                          totalCount: delivery.medicineLines.length,
                        ),
                        const _SectionBreak(),
                        _DetailSection(
                          title: 'Patient details',
                          child: _PatientDetailsGrid(delivery: delivery),
                        ),
                        const _SectionBreak(),
                        _DetailSection(
                          title: 'Medicines',
                          subtitle: isDispensed
                              ? 'Dispensed — status is read-only'
                              : 'Mark each medicine as Available, OOS, or Substitute',
                          child: _MedicinesResponsiveSection(
                            delivery: delivery,
                            readOnly: isDispensed,
                            onStatusChanged:
                                (line, availability, substitute) async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await PharmacyPrescriptionStore.instance
                                    .updateMedicineLine(
                                  deliveryId: delivery.id,
                                  medicineEntryId: line.medicineEntryId,
                                  availability: availability,
                                  substituteName: substitute,
                                );
                              } catch (_) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Failed to update medicine availability. Please retry.'),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  _DispensingPanel(
                    delivery: delivery,
                    notesController: _notesController,
                    isDispensed: isDispensed,
                    onDispense: () => _markDispensed(delivery),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PrescriptionHeader extends StatelessWidget {
  const _PrescriptionHeader({
    required this.delivery,
    required this.reviewedCount,
    required this.totalCount,
  });

  final PharmacyPrescriptionDelivery delivery;
  final int reviewedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final draft = delivery.draft;
    final status = _DeliveryStatusStyle.from(delivery.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.patient.patientName,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineLarge,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryOf(context),
                      letterSpacing: -0.5),
                ),
                SizedBox(height: 6),
                Text(
                  '${draft.patient.age} yrs · ${draft.patient.gender ?? '—'} · ${_pharmacyDoctorLabel(delivery.doctorName)}',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondaryOf(context)),
                ),
                SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 14, color: AppColors.textSecondaryOf(context)),
                    const SizedBox(width: 4),
                    Text(
                      'Received ${DateFormat('dd MMM yyyy, hh:mm a').format(delivery.sentAt)}',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () =>
                      PrescriptionPreviewModal.show(context, draft: draft),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Preview',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            fontWeight: FontWeight.w600,
                            color: AppColors.pharmacyGreen,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 15,
                          color: AppColors.pharmacyGreen,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.label,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w700,
                      color: status.color),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.cardBgOf(context),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$reviewedCount / $totalCount reviewed',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondaryOf(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeliveryStatusStyle {
  const _DeliveryStatusStyle({required this.label, required this.color});

  final String label;
  final Color color;

  static _DeliveryStatusStyle from(PharmacyDeliveryStatus status) =>
      switch (status) {
        PharmacyDeliveryStatus.sent =>
          _DeliveryStatusStyle(label: 'New', color: AppColors.doctorBlue),
        PharmacyDeliveryStatus.viewed =>
          _DeliveryStatusStyle(label: 'Viewed', color: const Color(0xFFCA8A04)),
        PharmacyDeliveryStatus.partiallyDispensed => _DeliveryStatusStyle(
            label: 'Partially dispensed', color: const Color(0xFFEA580C)),
        PharmacyDeliveryStatus.dispensed => _DeliveryStatusStyle(
            label: 'Dispensed', color: AppColors.pharmacyGreen),
      };
}

class _SectionBreak extends StatelessWidget {
  const _SectionBreak();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 16);
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection(
      {required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                          color: AppColors.pharmacyGreen,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  Text(title,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.headlineSmall,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context))),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 13),
                  child: Text(subtitle!,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context))),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

class _PatientDetailsGrid extends StatelessWidget {
  const _PatientDetailsGrid({required this.delivery});

  final PharmacyPrescriptionDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final draft = delivery.draft;
    final details = [
      ('Patient', draft.patient.patientName),
      (
        'Age / Gender',
        '${draft.patient.age} yrs · ${draft.patient.gender ?? '—'}'
      ),
      ('Doctor', _pharmacyDoctorLabel(delivery.doctorName)),
      ('Rx ID', draft.prescriptionId),
      ('Received', DateFormat('dd MMM yyyy, hh:mm a').format(delivery.sentAt)),
      if (draft.primaryDiagnosis.isNotEmpty)
        ('Diagnosis', draft.primaryDiagnosis),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: details.map((d) {
              return Container(
                width: isWide
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardBgOf(context),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.textPrimaryOf(context)
                            .withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.$1,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context),
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Text(d.$2,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyMedium,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context))),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _MedicinesResponsiveSection extends StatelessWidget {
  const _MedicinesResponsiveSection({
    required this.delivery,
    required this.readOnly,
    required this.onStatusChanged,
  });

  final PharmacyPrescriptionDelivery delivery;
  final bool readOnly;
  final Future<void> Function(MedicineDispenseLine line,
      MedicineAvailability availability, String substitute) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 750) {
          return _MedicinesTableSection(
            delivery: delivery,
            readOnly: readOnly,
            onStatusChanged: onStatusChanged,
          );
        } else {
          return _MedicinesListSection(
            delivery: delivery,
            readOnly: readOnly,
            onStatusChanged: onStatusChanged,
          );
        }
      },
    );
  }
}

class _MedicinesListSection extends StatelessWidget {
  const _MedicinesListSection({
    required this.delivery,
    required this.readOnly,
    required this.onStatusChanged,
  });

  final PharmacyPrescriptionDelivery delivery;
  final bool readOnly;
  final Future<void> Function(MedicineDispenseLine line,
      MedicineAvailability availability, String substitute) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final lines = delivery.medicineLines;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines.map((line) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.borderOf(context).withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                    color: AppColors.textPrimaryOf(context)
                        .withValues(alpha: 0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.medicineName,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _InfoChip(label: 'Dosage', value: line.dosageLabel),
                    _InfoChip(label: 'Form', value: line.form),
                    _InfoChip(label: 'Qty', value: line.quantity),
                    _InfoChip(label: 'Freq', value: line.frequencyLabel),
                    _InfoChip(label: 'Dur', value: line.durationLabel),
                  ],
                ),
                if (line.specialInstructions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Note: ${line.specialInstructions}',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                        fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1, color: _lineColor),
                const SizedBox(height: 12),
                _MedicineStatusPicker(
                  line: line,
                  readOnly: readOnly,
                  onChanged: (availability, substitute) =>
                      onStatusChanged(line, availability, substitute),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: GoogleFonts.inter(
                fontSize: AppTypography.labelSmall,
                color: AppColors.textSecondaryOf(context))),
        Text(value,
            style: GoogleFonts.inter(
                fontSize: AppTypography.labelSmall,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context))),
      ],
    );
  }
}

class _MedicinesTableSection extends StatelessWidget {
  const _MedicinesTableSection({
    required this.delivery,
    required this.readOnly,
    required this.onStatusChanged,
  });

  final PharmacyPrescriptionDelivery delivery;
  final bool readOnly;
  final Future<void> Function(MedicineDispenseLine line,
      MedicineAvailability availability, String substitute) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final lines = delivery.medicineLines;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.symmetric(
              inside: BorderSide(
                  color: AppColors.borderOf(context).withValues(alpha: 0.5),
                  width: 1)),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {
            0: FixedColumnWidth(28),
            1: FixedColumnWidth(180),
            2: FixedColumnWidth(70),
            3: FixedColumnWidth(75),
            4: FixedColumnWidth(40),
            5: FixedColumnWidth(55),
            6: FixedColumnWidth(65),
            7: FixedColumnWidth(120),
            8: FixedColumnWidth(230),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: _headerBg),
              children: [
                for (final h in [
                  '#',
                  'Medicine',
                  'Dosage',
                  'Form',
                  'Qty',
                  'Freq',
                  'Dur',
                  'Note',
                  'Status'
                ])
                  _HeaderCell(h),
              ],
            ),
            for (var i = 0; i < lines.length; i++)
              TableRow(
                decoration: BoxDecoration(
                  color: i.isEven
                      ? AppColors.surfaceOf(context)
                      : _headerBg.withValues(alpha: 0.45),
                ),
                children: [
                  _BodyCell('${i + 1}', align: TextAlign.center),
                  _BodyCell(lines[i].medicineName, bold: true),
                  _BodyCell(lines[i].dosageLabel),
                  _BodyCell(lines[i].form),
                  _BodyCell(lines[i].quantity),
                  _BodyCell(lines[i].frequencyLabel),
                  _BodyCell(lines[i].durationLabel),
                  _BodyCell(lines[i].specialInstructions.isEmpty
                      ? '—'
                      : lines[i].specialInstructions),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: _MedicineStatusPicker(
                      line: lines[i],
                      readOnly: readOnly,
                      onChanged: (availability, substitute) =>
                          onStatusChanged(lines[i], availability, substitute),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DispensingPanel extends StatelessWidget {
  const _DispensingPanel({
    required this.delivery,
    required this.notesController,
    required this.isDispensed,
    required this.onDispense,
  });

  final PharmacyPrescriptionDelivery delivery;
  final TextEditingController notesController;
  final bool isDispensed;
  final VoidCallback onDispense;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, -8)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                      color: AppColors.pharmacyGreen,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Text('Dispensing',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          if (isDispensed) ...[
            Text(
              'Dispensed ${delivery.dispensedAt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(delivery.dispensedAt!) : ''}',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: AppColors.pharmacyGreen),
            ),
            if (delivery.dispensingNotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  delivery.dispensingNotes,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.4),
                ),
              ),
          ] else ...[
            TextFormField(
              controller: notesController,
              maxLines: 2,
              style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
              decoration: InputDecoration(
                labelText: 'Dispensing notes (optional)',
                labelStyle:
                    GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                filled: true,
                fillColor: AppColors.cardBgOf(context),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _lineColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                      color: AppColors.pharmacyGreen, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: onDispense,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pharmacyGreen,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  'Mark as Dispensed',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF475569),
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell(
    this.text, {
    this.bold = false,
    this.align = TextAlign.left,
  }) : muted = false;

  final String text;
  final bool bold;
  final bool muted;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text.isEmpty ? '—' : text,
        textAlign: align,
        style: GoogleFonts.inter(
          fontSize: AppTypography.labelMedium,
          height: 1.35,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: muted
              ? AppColors.textSecondaryOf(context)
              : AppColors.textPrimaryOf(context),
        ),
      ),
    );
  }
}

class _MedicineStatusPicker extends StatelessWidget {
  const _MedicineStatusPicker({
    required this.line,
    required this.readOnly,
    required this.onChanged,
  });

  final MedicineDispenseLine line;
  final bool readOnly;
  final void Function(MedicineAvailability availability, String substitute)
      onChanged;

  Future<void> _showSubstituteDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: line.substituteName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Substitute medicine'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Substitute name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      onChanged(MedicineAvailability.substituted, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatusSegment(
                label: 'Available',
                selected: line.availability == MedicineAvailability.available,
                color: AppColors.pharmacyGreen,
                onTap: readOnly
                    ? null
                    : () => onChanged(MedicineAvailability.available, ''),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _StatusSegment(
                label: 'OOS',
                selected: line.availability == MedicineAvailability.outOfStock,
                color: AppColors.error,
                onTap: readOnly
                    ? null
                    : () => onChanged(MedicineAvailability.outOfStock, ''),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _StatusSegment(
                label: 'Substitute',
                selected: line.availability == MedicineAvailability.substituted,
                color: AppColors.doctorBlue,
                onTap: readOnly ? null : () => _showSubstituteDialog(context),
              ),
            ),
          ],
        ),
        if (line.availability == MedicineAvailability.substituted &&
            line.substituteName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              line.substituteName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 10, color: AppColors.doctorBlue, height: 1.3),
            ),
          ),
      ],
    );
  }
}

class _StatusSegment extends StatelessWidget {
  const _StatusSegment({
    required this.label,
    required this.selected,
    required this.color,
    this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Opacity(
          opacity: (disabled && !selected) ? 0.4 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? color
                  : (disabled
                      ? AppColors.surfaceOf(context)
                      : AppColors.cardBgOf(context)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelSmall,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected
                    ? AppColors.surfaceOf(context)
                    : (disabled
                        ? AppColors.textPrimaryOf(context)
                        : AppColors.textSecondaryOf(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
