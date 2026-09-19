import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import 'models/clinical_models.dart';
import 'notes/clinical_notes_screen.dart';
import 'prescription/write_prescription_screen.dart';
import '../../../core/theme/app_typography.dart';

class ClinicalToolsShell extends StatefulWidget {
  const ClinicalToolsShell({
    super.key,
    required this.patient,
    this.initialTab = 0,
    this.existingDraft,
  });

  final PatientClinicalContext patient;
  final int initialTab;
  final PrescriptionDraft? existingDraft;

  static Future<void> open(
    BuildContext context, {
    required PatientClinicalContext patient,
    int initialTab = 0,
    PrescriptionDraft? existingDraft,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicalToolsShell(
          patient: patient,
          initialTab: initialTab,
          existingDraft: existingDraft,
        ),
      ),
    );
  }

  static Future<void> openForEdit(
    BuildContext context, {
    required PatientClinicalContext patient,
    required PrescriptionDraft draft,
  }) {
    return open(context, patient: patient, existingDraft: draft.copy());
  }

  @override
  State<ClinicalToolsShell> createState() => _ClinicalToolsShellState();
}

class _ClinicalToolsShellState extends State<ClinicalToolsShell>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        title: Text('Prescribe — ${widget.patient.patientName}'),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.doctorBlue,
          unselectedLabelColor: AppColors.textSecondaryOf(context),
          indicatorColor: AppColors.doctorBlue,
          labelStyle: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Prescription'),
            Tab(text: 'Notes'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveLayout.contentMaxWidth(context)),
          child: TabBarView(
            controller: _tabController,
            children: [
              WritePrescriptionScreen(
                patient: widget.patient,
                existingDraft: widget.existingDraft,
              ),
              ClinicalNotesScreen(patient: widget.patient),
            ],
          ),
        ),
      ),
    );
  }
}
