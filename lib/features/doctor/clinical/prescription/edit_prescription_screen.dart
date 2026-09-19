import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/clinical_models.dart';
import 'write_prescription_screen.dart';
import '../../../../core/theme/app_typography.dart';

class EditPrescriptionScreen extends StatelessWidget {
  const EditPrescriptionScreen({
    super.key,
    required this.patient,
    required this.draft,
  });

  final PatientClinicalContext patient;
  final PrescriptionDraft draft;

  static Future<void> open(
    BuildContext context, {
    required PatientClinicalContext patient,
    required PrescriptionDraft draft,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditPrescriptionScreen(
          patient: patient,
          draft: draft.copy(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        title: const Text('Edit Prescription'),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontSize: AppTypography.headlineSmall,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryOf(context),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveLayout.contentMaxWidth(context)),
          child: WritePrescriptionScreen(
            patient: patient,
            existingDraft: draft,
            showPreviousPrescriptions: false,
          ),
        ),
      ),
    );
  }
}
