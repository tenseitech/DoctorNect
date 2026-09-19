import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/session/patient_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../doctor/clinical/data/clinical_prescription_store.dart';
import '../../../doctor/clinical/models/clinical_models.dart';
import '../../../doctor/clinical/prescription/prescription_pdf_service.dart';
import '../../../doctor/clinical/prescription/prescription_preview_modal.dart';
import '../../../pharmacy/data/pharmacy_prescription_store.dart';
import '../widgets/patient_profile_form_styles.dart';
import 'patient_pharmacy_status.dart';
import '../../../../core/theme/app_typography.dart';

class MyPrescriptionsScreen extends StatefulWidget {
  const MyPrescriptionsScreen({super.key});

  @override
  State<MyPrescriptionsScreen> createState() => _MyPrescriptionsScreenState();
}

class _MyPrescriptionsScreenState extends State<MyPrescriptionsScreen> {
  static const _loadTimeout = Duration(seconds: 12);

  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrescriptions());
  }

  Future<void> _loadPrescriptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      await Future.wait([
        ClinicalPrescriptionStore.instance
            .refreshForPatient(patientId, preferCache: true)
            .timeout(_loadTimeout),
        PharmacyPrescriptionStore.instance
            .refreshForPatient(patientId, preferCache: true)
            .timeout(_loadTimeout),
      ]);
    } on TimeoutException {
      if (mounted) {
        setState(() =>
            _loadError = 'Could not load prescriptions. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _loadError = 'Could not load prescriptions. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PrescriptionDraft> _patientPrescriptions() {
    return ClinicalPrescriptionStore.instance
        .forPatient(PatientSession.loggedInPatientId);
  }

  PatientPharmacyStatus? _pharmacyStatusFor(String prescriptionId) {
    final patientId = PatientSession.loggedInPatientId;
    final deliveries = PharmacyPrescriptionStore.instance.forPrescription(
      prescriptionId: prescriptionId,
      patientId: patientId,
    );
    if (deliveries.isEmpty) return null;

    final delivery = deliveries.first;
    return PatientPharmacyStatus(
      storeName: delivery.storeName,
      status: delivery.status,
      sentAt: delivery.sentAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ClinicalPrescriptionStore.instance,
        PharmacyPrescriptionStore.instance,
      ]),
      builder: (context, _) {
        final list = _patientPrescriptions();

        return Scaffold(
          backgroundColor: AppColors.cardBgOf(context),
          appBar: PatientProfileFormStyles.profileAppBar('My Prescriptions',
              context: context),
          body: _buildBody(list),
        );
      },
    );
  }

  Widget _buildBody(List<PrescriptionDraft> list) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.patientTeal),
      );
    }

    if (_loadError != null) {
      return PatientProfileFormStyles.constrainedScrollBody(
        child: _PrescriptionsMessageState(
          icon: Icons.cloud_off_outlined,
          title: _loadError!,
          subtitle: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: _loadPrescriptions,
        ),
      );
    }

    if (list.isEmpty) {
      return PatientProfileFormStyles.constrainedScrollBody(
        child: const _PrescriptionsMessageState(
          icon: AppIcons.prescription,
          title: 'No prescriptions yet',
          subtitle: 'Prescriptions from your doctors will appear here.',
        ),
      );
    }

    return PatientProfileFormStyles.constrainedScrollBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: list.map((draft) {
          final pharmacyStatus = _pharmacyStatusFor(draft.prescriptionId);
          return PatientProfileFormStyles.recordItemCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(AppIcons.prescription,
                        color: AppColors.patientTeal, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            draft.primaryDiagnosis.isEmpty
                                ? 'Prescription'
                                : draft.primaryDiagnosis,
                            style:
                                GoogleFonts.inter(fontWeight: FontWeight.w600),
                          ),
                          if (draft.doctorName.isNotEmpty)
                            Text(
                              draft.doctorName,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.labelMedium,
                                color: AppColors.patientTeal,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (draft.clinicName.isNotEmpty)
                            Text(
                              draft.clinicName,
                              style: GoogleFonts.inter(
                                  fontSize: AppTypography.labelSmall,
                                  color: AppColors.textSecondaryOf(context)),
                            ),
                          Text(
                            DateFormat('dd MMM yyyy')
                                .format(draft.prescriptionDate),
                            style: GoogleFonts.inter(
                                fontSize: AppTypography.labelMedium,
                                color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                      onPressed: () =>
                          PrescriptionPreviewModal.show(context, draft: draft),
                    ),
                    TextButton(
                      onPressed: () => PrescriptionPdfService.sharePdf(draft),
                      child: const Text('Download'),
                    ),
                  ],
                ),
                if (pharmacyStatus != null) ...[
                  const SizedBox(height: 8),
                  PatientPharmacyStatusChip(status: pharmacyStatus),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PrescriptionsMessageState extends StatelessWidget {
  const _PrescriptionsMessageState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth =
            PatientProfileFormStyles.resolveContentWidth(context, constraints);

        return Center(
          child: SizedBox(
            width: contentWidth,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      size: 64,
                      color: AppColors.patientTeal.withValues(alpha: 0.35)),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.bodySmall,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: onAction,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.patientTeal),
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
