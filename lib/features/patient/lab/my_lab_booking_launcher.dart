import '../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../doctor/clinical/data/community_investigations_repository.dart';
import '../../doctor/clinical/models/clinical_models.dart' hide LabTestItem;
import '../../doctor/clinical/prescription/widgets/prescription_form_sections.dart';
import '../profile/data/patient_profile_mock.dart';
import '../data/patient_favorites_store.dart';
import 'lab_booking_flow_screen.dart';
import 'utils/patient_lab_age_guard.dart';
import 'utils/patient_selected_investigations_mapper.dart';
import 'package:medibond/features/shared/widgets/lab_page_layout.dart';

Future<void> showMyLabTestPickerAndBook(BuildContext context, SavedLabEntry lab) async {
  final patientId = PatientSession.loggedInPatientId;
  if (patientId.isEmpty) {
    AppToast.info(context, 'Please sign in as a patient to book a lab test.');
    return;
  }

  await Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => MyLabBookTestsScreen(lab: lab)),
  );
}

class MyLabBookTestsScreen extends StatefulWidget {
  const MyLabBookTestsScreen({super.key, required this.lab});

  final SavedLabEntry lab;

  @override
  State<MyLabBookTestsScreen> createState() => _MyLabBookTestsScreenState();
}

class _MyLabBookTestsScreenState extends State<MyLabBookTestsScreen> {
  late final PrescriptionDraft _investigationsDraft;

  @override
  void initState() {
    super.initState();
    final profile = PatientProfileMock.profile;
    _investigationsDraft = PrescriptionDraft(
      patient: PatientClinicalContext(
        patientName: profile.name.isNotEmpty ? profile.name : PatientSession.loggedInPatientName,
        age: profile.age,
        gender: profile.gender,
        patientId: PatientSession.loggedInPatientId,
      ),
    );
    unawaited(CommunityInvestigationsRepository.instance.fetchAll());
  }

  int _selectedInvestigationCount() {
    return _investigationsDraft.validInvestigations.length + _investigationsDraft.bodyParts.length;
  }

  void _proceedWithSelectedTests() {
    final tests = PatientSelectedInvestigationsMapper.toLabTests(_investigationsDraft);
    if (tests.isEmpty) {
      AppToast.info(context, 'Select at least one test to continue.');
      return;
    }

    if (!PatientLabAgeGuard.profileAgeValid()) {
      AppToast.info(context, PatientLabAgeGuard.missingAgeSnackbarMessage);
      return;
    }

    final partnerLab = widget.lab.toPartnerLab();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LabBookingFlowScreen(
          tests: tests,
          partnerLabs: [partnerLab],
          preselectedLab: partnerLab,
          lockSelectedLab: true,
          submitAsRequest: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);
    final selectedCount = _selectedInvestigationCount();
    final profileAgeValid = PatientLabAgeGuard.profileAgeValid();
    final labName = widget.lab.name.trim();

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: LabPageLayout.appBar(
        context,
        title: 'Select tests',
        onBack: () => Navigator.pop(context),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: LabPageLayout.contentWidth(context)),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 20,
              compact ? 12 : 16,
              compact ? 16 : 20,
              compact ? 24 : 28,
            ),
            children: [
              Text(
                labName.isEmpty ? 'Book lab tests' : 'Book at $labName',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose tests below, then continue to complete your booking request.',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context), height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: LabPageLayout.cardDecoration(),
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 16,
                  compact ? 14 : 16,
                  compact ? 14 : 16,
                  compact ? 14 : 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!profileAgeValid) ...[
                      Text(
                        'Booking for ${PatientLabAgeGuard.selfAgeLabel()}',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        PatientLabAgeGuard.missingAgeHint,
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.error, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                    ],
                    PrescriptionInvestigationsSection(
                      draft: _investigationsDraft,
                      allowCustomTests: false,
                      allowClinicalNotes: false,
                      onChanged: () => setState(() {}),
                      collapsible: true,
                      initiallyExpanded: true,
                    ),
                    if (selectedCount > 0) ...[
                      const SizedBox(height: 16),
                      LabPrimaryButton(
                        label: 'Proceed with selected tests ($selectedCount)',
                        enabled: profileAgeValid,
                        onPressed: _proceedWithSelectedTests,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
