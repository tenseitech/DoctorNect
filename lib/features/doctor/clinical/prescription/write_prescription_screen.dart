import '../../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/notifications/patient_notification_emitter.dart';
import '../lab/lab_order_service.dart';
import 'edit_prescription_screen.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../patient/profile/data/patient_profile_mock.dart';
import '../../../lab/data/lab_connection_store.dart';
import '../../../pharmacy/data/pharmacy_connection_store.dart';
import '../../../pharmacy/data/medical_store_registry.dart';
import '../../../pharmacy/data/pharmacy_prescription_store.dart';
import '../../pharmacy/send_to_pharmacy_sheet.dart';
import '../../profile/data/doctor_profile_store.dart';
import '../data/clinical_prescription_store.dart';
import '../data/community_diagnosis_repository.dart';
import '../data/community_medicine_repository.dart';
import '../data/prescription_clinical_assets.dart';
import '../data/patient_clinical_baseline_loader.dart';
import '../models/clinical_models.dart';
import '../refer_patient_service.dart';
import '../widgets/clinical_widgets.dart';
import '../widgets/refer_specialist_dialog.dart';
import 'patient_prescription_history_screen.dart';
import 'prescription_desktop_rx_section.dart';
import 'prescription_mobile_rx_section.dart';
import 'prescription_preview_modal.dart';
import 'prescription_rx_shared.dart';
import 'widgets/prescription_form_sections.dart';

class WritePrescriptionScreen extends StatefulWidget {
  const WritePrescriptionScreen({
    super.key,
    required this.patient,
    this.existingDraft,
    this.showPreviousPrescriptions = true,
  });

  final PatientClinicalContext patient;
  final PrescriptionDraft? existingDraft;
  final bool showPreviousPrescriptions;

  @override
  State<WritePrescriptionScreen> createState() => _WritePrescriptionScreenState();
}

class _WritePrescriptionScreenState extends State<WritePrescriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  late PrescriptionDraft _draft;

  final _chiefComplaintController = TextEditingController();
  final _primaryDxController = TextEditingController();
  final _secondaryDxController = TextEditingController();
  final _symptomsController = TextEditingController();
  final _durationController = TextEditingController();
  final _pastHistoryController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _bpController = TextEditingController();
  final _tempController = TextEditingController();
  final _pulseController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _heightController = TextEditingController();
  final _respiratoryRateController = TextEditingController();
  final _generalExaminationController = TextEditingController();
  final _weightController = TextEditingController();
  final _dietController = TextEditingController();
  final _activityController = TextEditingController();
  final _lifestyleController = TextEditingController();
  final _generalAdviceController = TextEditingController();
  final _followUpNoteController = TextEditingController();

  final Map<String, TextEditingController> _nameControllers = {};
  bool _isLoadedFromSavedRecord = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingDraft;
    if (existing != null) {
      _draft = existing.copy();
      _isLoadedFromSavedRecord = true;
      _applyDraftToControllers(_draft);
      _initMedicineControllers();
    } else {
      _draft = PrescriptionDraft(patient: widget.patient);
      if (widget.patient.weightKg != null) {
        _weightController.text = '${widget.patient.weightKg}';
        _draft.vitals.weightKg = _weightController.text;
      }
      _initMedicineControllers();
      _prefillAppointmentDetails();
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefillAppointmentDetails());
      unawaited(_prefillPatientBaseline());
    }
    PrescriptionClinicalAssets.scheduleIdleLoad(() {
      if (mounted) setState(() {});
    });
  }

  void _prefillAppointmentDetails() {
    final appointmentId = widget.patient.appointmentId;
    if (appointmentId == null || appointmentId.isEmpty) return;

    final record = SharedAppointmentsStore.instance.findRecordById(appointmentId);
    if (record == null) return;

    if (_chiefComplaintController.text.trim().isEmpty && record.chiefComplaints.isNotEmpty) {
      final joined = record.chiefComplaints.join(', ');
      _chiefComplaintController.text = joined;
      _draft.chiefComplaint = joined;
    }

    if (_symptomsController.text.trim().isEmpty && record.symptoms.isNotEmpty) {
      final joined = record.symptoms.join(', ');
      _symptomsController.text = joined;
      _draft.symptoms = joined;
    }
  }

  Future<void> _prefillPatientBaseline() async {
    final patientId = widget.patient.patientId ?? '';
    if (patientId.isEmpty) return;

    try {
      final baseline = await PatientClinicalBaselineLoader.fetchLatestBaselineDraft(patientId);
      if (!mounted) return;

      if (baseline != null) {
        PatientClinicalBaselineLoader.applyBaseline(
          target: _draft,
          source: baseline,
          setFieldIfEmpty: _setBaselineFieldIfEmpty,
        );
      }

      if (_allergiesController.text.trim().isEmpty) {
        final profileAllergies =
            await PatientClinicalBaselineLoader.fetchProfileAllergiesText(patientId);
        if (!mounted) return;
        if (profileAllergies != null && profileAllergies.isNotEmpty) {
          _allergiesController.text = profileAllergies;
          _draft.allergies = profileAllergies;
        }
      }

      if (mounted) setState(() {});
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('WritePrescriptionScreen._prefillPatientBaseline failed: $e\n$st');
      }
    }
  }

  void _setBaselineFieldIfEmpty(String field, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    switch (field) {
      case 'heightCm':
        if (_heightController.text.trim().isEmpty) {
          _heightController.text = trimmed;
          _draft.vitals.heightCm = trimmed;
        }
      case 'weightKg':
        if (_weightController.text.trim().isEmpty) {
          _weightController.text = trimmed;
          _draft.vitals.weightKg = trimmed;
        }
      case 'bloodPressure':
        if (_bpController.text.trim().isEmpty) {
          _bpController.text = trimmed;
          _draft.vitals.bloodPressure = trimmed;
        }
      case 'temperature':
        if (_tempController.text.trim().isEmpty) {
          _tempController.text = trimmed;
          _draft.vitals.temperature = trimmed;
        }
      case 'pulse':
        if (_pulseController.text.trim().isEmpty) {
          _pulseController.text = trimmed;
          _draft.vitals.pulse = trimmed;
        }
      case 'spo2':
        if (_spo2Controller.text.trim().isEmpty) {
          _spo2Controller.text = trimmed;
          _draft.vitals.spo2 = trimmed;
        }
      case 'respiratoryRate':
        if (_respiratoryRateController.text.trim().isEmpty) {
          _respiratoryRateController.text = trimmed;
          _draft.vitals.respiratoryRate = trimmed;
        }
      case 'generalExamination':
        if (_generalExaminationController.text.trim().isEmpty) {
          _generalExaminationController.text = trimmed;
          _draft.generalExamination = trimmed;
        }
      case 'pastHistory':
        if (_pastHistoryController.text.trim().isEmpty) {
          _pastHistoryController.text = trimmed;
          _draft.pastHistory = trimmed;
        }
      case 'allergies':
        if (_allergiesController.text.trim().isEmpty) {
          _allergiesController.text = trimmed;
          _draft.allergies = trimmed;
        }
    }
  }

  void _initMedicineControllers() {
    _draft.medicines.removeWhere((m) => m.name.trim().isEmpty);
    for (final m in _draft.medicines) {
      _nameControllers[m.id] = TextEditingController(text: m.name);
    }
  }

  void _applyDraftToControllers(PrescriptionDraft draft) {
    _chiefComplaintController.text = draft.chiefComplaint;
    _primaryDxController.text = draft.primaryDiagnosis;
    _secondaryDxController.text = draft.secondaryDiagnosis;
    _symptomsController.text = draft.symptoms;
    _durationController.text = draft.symptomDuration;
    _pastHistoryController.text = draft.pastHistory;
    _allergiesController.text = draft.allergies;
    _bpController.text = draft.vitals.bloodPressure;
    _tempController.text = draft.vitals.temperature;
    _pulseController.text = draft.vitals.pulse;
    _spo2Controller.text = draft.vitals.spo2;
    _heightController.text = draft.vitals.heightCm;
    _respiratoryRateController.text = draft.vitals.respiratoryRate;
    _weightController.text = draft.vitals.weightKg;
    _generalExaminationController.text = draft.generalExamination;
    _dietController.text = draft.dietAdvice;
    _activityController.text = draft.activityRestrictions;
    _lifestyleController.text = draft.lifestyleAdvice;
    _generalAdviceController.text = draft.generalAdvice;
    _followUpNoteController.text = draft.followUpNote;
  }

  void _loadPrescriptionForEdit(PrescriptionDraft draft) {
    EditPrescriptionScreen.open(
      context,
      patient: widget.patient,
      draft: draft,
    );
  }

  @override
  void dispose() {
    _chiefComplaintController.dispose();
    _primaryDxController.dispose();
    _secondaryDxController.dispose();
    _symptomsController.dispose();
    _durationController.dispose();
    _pastHistoryController.dispose();
    _allergiesController.dispose();
    _bpController.dispose();
    _tempController.dispose();
    _pulseController.dispose();
    _spo2Controller.dispose();
    _heightController.dispose();
    _respiratoryRateController.dispose();
    _generalExaminationController.dispose();
    _weightController.dispose();
    _dietController.dispose();
    _activityController.dispose();
    _lifestyleController.dispose();
    _generalAdviceController.dispose();
    _followUpNoteController.dispose();
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncDraftFromControllers() {
    _draft.chiefComplaint = _chiefComplaintController.text;
    _draft.primaryDiagnosis = _primaryDxController.text;
    _draft.secondaryDiagnosis = _secondaryDxController.text;
    _draft.symptoms = _symptomsController.text;
    _draft.symptomDuration = _durationController.text;
    _draft.pastHistory = _pastHistoryController.text;
    _draft.allergies = _allergiesController.text;
    _draft.vitals.bloodPressure = _bpController.text;
    _draft.vitals.temperature = _tempController.text;
    _draft.vitals.pulse = _pulseController.text;
    _draft.vitals.spo2 = _spo2Controller.text;
    _draft.vitals.heightCm = _heightController.text;
    _draft.vitals.respiratoryRate = _respiratoryRateController.text;
    _draft.vitals.weightKg = _weightController.text;
    _draft.generalExamination = _generalExaminationController.text;
    _draft.dietAdvice = _dietController.text;
    _draft.activityRestrictions = _activityController.text;
    _draft.lifestyleAdvice = _lifestyleController.text;
    _draft.generalAdvice = _generalAdviceController.text;
    _draft.followUpNote = _followUpNoteController.text;
    for (final m in _draft.medicines) {
      m.name = _nameControllers[m.id]?.text ?? m.name;
    }
  }

  void _onFieldChanged() {
    _syncDraftFromControllers();
  }

  void _onDraftStructureChanged() {
    _syncDraftFromControllers();
    setState(() {});
  }

  void _addMedicineAfter(int index) {
    setState(() {
      final entry = MedicineEntry();
      final insertAt = index.clamp(-1, _draft.medicines.length - 1) + 1;
      _draft.medicines.insert(insertAt, entry);
      _nameControllers[entry.id] = TextEditingController();
    });
  }

  void _removeMedicine(int index) {
    if (index < 0 || index >= _draft.medicines.length) return;
    setState(() {
      final id = _draft.medicines[index].id;
      _nameControllers[id]?.dispose();
      _nameControllers.remove(id);
      _draft.medicines.removeAt(index);
    });
  }

  void _selectMedicineFromSuggestion(MedicineSearchSuggestion item) {
    final normalized = item.name.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final duplicate = _draft.medicines.any(
      (m) => m.name.trim().toLowerCase() == normalized,
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.name.trim()} is already in this Rx'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      final entry = MedicineEntry();
      entry.name = item.name.trim();
      if (item.dosageUnit != null && item.dosageUnit!.isNotEmpty) {
        entry.dosageUnit = item.dosageUnit!;
      }
      if (item.form != null && item.form!.isNotEmpty) {
        entry.form = item.form!;
      }
      _draft.medicines.add(entry);
      _nameControllers[entry.id] = TextEditingController(text: entry.name);
    });
    _onDraftStructureChanged();
  }

  Future<void> _pickNextVisitDate() async {
    final initial = _draft.nextVisit ?? DateTime.now().add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.doctorBlue),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _draft.nextVisit = picked);
  }

  void _preview() {
    _syncDraftFromControllers();
    if (_formKey.currentState?.validate() == false) return;
    final error = _draft.validateForSubmit();
    if (error != null) {
      AppToast.info(context, error);
      return;
    }
    PrescriptionPreviewModal.show(context, draft: _draft);
  }

  Future<void> _saveEmr() async {
    _syncDraftFromControllers();
    if (_formKey.currentState?.validate() == false) return;
    final error = _draft.validateForSubmit();
    if (error != null) {
      AppToast.info(context, error);
      return;
    }
    if (!_draft.hasResolvedPatientId) {
      // FIXED: block save when the patient id is unresolved instead of writing a record the patient can never read
      AppToast.info(context, 'This patient is not registered yet — the prescription cannot be saved to their record.');
      return;
    }
    final doctorName = DoctorProfileStore.displayName;
    final doctorId = DoctorSession.loggedInDoctorId.trim();
    if (doctorId.isNotEmpty) {
      await Future.wait([
        CommunityDiagnosisRepository.instance.persistCustomIfNeeded(
          _draft.primaryDiagnosis,
          doctorId: doctorId,
        ),
        CommunityDiagnosisRepository.instance.persistCustomIfNeeded(
          _draft.secondaryDiagnosis,
          doctorId: doctorId,
        ),
      ]);
    }
    try {
      await ClinicalPrescriptionStore.instance.save(_draft);
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context, 'Failed to save prescription. Please check your connection and try again.');
      return;
    }

    try {
      final pendingReferrals = _draft.referrals.where((r) => !r.sent).length;
      if (pendingReferrals > 0) {
        await ReferPatientService.sendPendingReferrals(
          patient: widget.patient,
          referrals: _draft.referrals,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message
                : 'Prescription saved, but sending referral(s) failed. Please retry from Refer.',
          ),
        ),
      );
    }
    if (!mounted) return;
    PatientProfileMock.syncPrescriptionFromDraft(_draft, doctorName: doctorName);

    final appointmentId = widget.patient.appointmentId;
    if (appointmentId != null && appointmentId.isNotEmpty) {
      try {
        await SharedAppointmentsStore.instance.saveConsultationOutcome(
          recordId: appointmentId,
          diagnosis: _draft.primaryDiagnosis,
          hasPrescription: true,
          markCompleted: true,
        );
      } catch (_) {
        if (!mounted) return;
        AppToast.info(context, 'Prescription saved, but appointment record not updated. Please retry.');
      }
    }

    final connections = PharmacyConnectionStore.instance.activeForDoctor(doctorId);
    if (!mounted) return;
    final storeIds = connections.isEmpty
        ? <String>[]
        : await SendToPharmacySheet.show(context, _draft);
    if (!mounted) return;
    if (storeIds != null && storeIds.isNotEmpty) {
      try {
        final sent = await PharmacyPrescriptionStore.instance.sendToStores( // FIXED: await so send failures surface
          draft: _draft,
          storeIds: storeIds,
          doctorId: doctorId,
          doctorName: doctorName,
        );
        if (!mounted) return; // FIXED: mounted check after await
        if (sent.isNotEmpty) {
          showClinicalToast(
            context,
            _isLoadedFromSavedRecord
                ? 'Prescription updated and sent to ${sent.length} medical store(s)'
                : 'Prescription saved and sent to ${sent.length} medical store(s)',
          );
        }
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prescription saved, but sending to the pharmacy failed. Please retry from Send.')), // FIXED
        );
      }
    } else {
      final message = _isLoadedFromSavedRecord
          ? (connections.isEmpty
              ? 'Prescription updated in EMR'
              : 'Prescription updated in EMR — use Send to notify recipients')
          : (connections.isEmpty
              ? 'Prescription saved to EMR (no connected stores)'
              : 'Prescription saved to EMR');
      showClinicalToast(context, message);
    }
  }

  Future<void> _showSendTo() async {
    _syncDraftFromControllers();
    if (_formKey.currentState?.validate() == false) return;
    final error = _draft.validateForSubmit();
    if (error != null) {
      if (mounted) AppToast.info(context, error);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SendToSheet(draft: _draft, patient: widget.patient),
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientPrescriptionHistoryScreen(patient: widget.patient),
      ),
    );
  }

  void _openReferDialog() {
    ReferSpecialistDialog.show(
      context,
      patient: widget.patient,
      initialReferrals: _draft.referrals,
      onReferralsChanged: (referrals) {
        setState(() {
          _draft.referrals = referrals
              .map(
                (r) => ReferralEntry(
                  doctorId: r.doctorId,
                  doctorName: r.doctorName,
                  specialization: r.specialization,
                  reason: r.reason,
                  sent: r.sent,
                ),
              )
              .toList();
        });
      },
    );
  }

  void _removeReferral(int index) {
    setState(() => _draft.referrals.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);
    final doctorSummary = DoctorProfileStore.displayNameWithPrefix;
    final patientSummary = '${widget.patient.patientName} · ${widget.patient.age} yrs';
    final medCount = namedMedicineEntries(_draft.medicines).length;
    final medSummary = medCount == 0 ? 'Add from catalog' : '$medCount medicine${medCount == 1 ? '' : 's'}';

    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              children: [
                if (_isLoadedFromSavedRecord) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.doctorBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.doctorBlue.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18, color: AppColors.doctorBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Editing · ${DateFormat('dd MMM yyyy, hh:mm a').format(_draft.prescriptionDate)} · ${_draft.prescriptionId}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.doctorBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!compact)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: PrescriptionHeaderSection(
                          draft: _draft,
                          collapsible: true,
                          initiallyExpanded: false,
                          collapsedSummary: doctorSummary,
                          dense: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PrescriptionPatientSection(
                          draft: _draft,
                          weightController: _weightController,
                          onChanged: _onFieldChanged,
                          collapsible: true,
                          initiallyExpanded: false,
                          collapsedSummary: patientSummary,
                          dense: true,
                        ),
                      ),
                    ],
                  )
                else ...[
                  PrescriptionHeaderSection(
                    draft: _draft,
                    collapsible: true,
                    initiallyExpanded: false,
                    collapsedSummary: doctorSummary,
                    dense: true,
                  ),
                  PrescriptionPatientSection(
                    draft: _draft,
                    weightController: _weightController,
                    onChanged: _onFieldChanged,
                    collapsible: true,
                    initiallyExpanded: false,
                    collapsedSummary: patientSummary,
                    dense: true,
                  ),
                ],
                if (widget.showPreviousPrescriptions)
                  _PreviousPrescriptionsSection(
                    patient: widget.patient,
                    activePrescriptionId: _draft.prescriptionId,
                    onEdit: _loadPrescriptionForEdit,
                  ),
                PrescriptionClinicalSection(
                  draft: _draft,
                  chiefComplaintController: _chiefComplaintController,
                  primaryDxController: _primaryDxController,
                  secondaryDxController: _secondaryDxController,
                  symptomsController: _symptomsController,
                  durationController: _durationController,
                  pastHistoryController: _pastHistoryController,
                  allergiesController: _allergiesController,
                  bpController: _bpController,
                  tempController: _tempController,
                  pulseController: _pulseController,
                  spo2Controller: _spo2Controller,
                  heightController: _heightController,
                  respiratoryRateController: _respiratoryRateController,
                  generalExaminationController: _generalExaminationController,
                  onChanged: _onDraftStructureChanged,
                  collapsible: true,
                  initiallyExpanded: false,
                  dense: true,
                ),
                if (!compact)
                  ClinicalSectionCard(
                    title: 'Rx Medicines',
                    dense: true,
                    collapsedSummary: medSummary,
                    child: PrescriptionDesktopRxSection(
                      medicines: _draft.medicines,
                      nameControllers: _nameControllers,
                      onAddAfter: _addMedicineAfter,
                      onRemove: _removeMedicine,
                      onChanged: _onDraftStructureChanged,
                      onMedicineSelected: _selectMedicineFromSuggestion,
                    ),
                  )
                else
                  ClinicalSectionCard(
                    title: 'Rx Medicines',
                    dense: true,
                    collapsedSummary: medSummary,
                    child: PrescriptionMobileRxSection(
                      medicines: _draft.medicines,
                      nameControllers: _nameControllers,
                      onAddAfter: _addMedicineAfter,
                      onRemove: _removeMedicine,
                      onChanged: _onDraftStructureChanged,
                      onMedicineSelected: _selectMedicineFromSuggestion,
                    ),
                  ),
                PrescriptionInvestigationsSection(
                  draft: _draft,
                  onChanged: _onDraftStructureChanged,
                  collapsible: true,
                  initiallyExpanded: false,
                  dense: true,
                ),
                PrescriptionAdviceSection(
                  dietController: _dietController,
                  activityController: _activityController,
                  lifestyleController: _lifestyleController,
                  generalAdviceController: _generalAdviceController,
                  onChanged: _onFieldChanged,
                  collapsible: true,
                  initiallyExpanded: false,
                  dense: true,
                  includeFollowUp: true,
                  draft: _draft,
                  followUpNoteController: _followUpNoteController,
                  onPickNextVisit: _pickNextVisitDate,
                ),
                PrescriptionReferralsSection(
                  draft: _draft,
                  onOpenReferDialog: _openReferDialog,
                  onRemoveReferral: _removeReferral,
                  collapsible: true,
                  initiallyExpanded: false,
                  dense: true,
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              border: Border(top: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.65))),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
              14,
              10,
              14,
              10 + MediaQuery.paddingOf(context).bottom,
            ),
            child: PrescriptionPractoActions(
              onPreview: _preview,
              onSave: _saveEmr,
              onShare: _showSendTo,
              onHistory: _openHistory,
              saveLabel: _isLoadedFromSavedRecord ? 'Update' : 'Save',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Previous Prescriptions Section ──────────────────────────────────────────

class _PreviousPrescriptionsSection extends StatefulWidget {
  const _PreviousPrescriptionsSection({
    required this.patient,
    required this.activePrescriptionId,
    required this.onEdit,
  });
  final PatientClinicalContext patient;
  final String activePrescriptionId;
  final ValueChanged<PrescriptionDraft> onEdit;

  @override
  State<_PreviousPrescriptionsSection> createState() => _PreviousPrescriptionsSectionState();
}

class _PreviousPrescriptionsSectionState extends State<_PreviousPrescriptionsSection> {
  String get _patientId => widget.patient.patientId ?? '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ClinicalPrescriptionStore.instance,
      builder: (context, _) {
        final records = ClinicalPrescriptionStore.instance.forPatient(_patientId);
        if (records.isEmpty) return const SizedBox.shrink();

        final latestRecords = records.take(2).toList();
        final summary = records.length == 1
            ? '1 saved'
            : 'Latest ${latestRecords.length} of ${records.length}';

        return ClinicalSectionCard(
          title: 'Previous prescriptions',
          collapsible: true,
          initiallyExpanded: false,
          dense: true,
          collapsedSummary: summary,
          child: Column(
            children: [
              for (var i = 0; i < latestRecords.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.borderOf(context).withValues(alpha: 0.5)),
                _PrevRxCard(
                  draft: latestRecords[i],
                  isActive: latestRecords[i].prescriptionId == widget.activePrescriptionId,
                  onEdit: () => widget.onEdit(latestRecords[i].copy()),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PrevRxCard extends StatelessWidget {
  const _PrevRxCard({
    required this.draft,
    required this.isActive,
    required this.onEdit,
  });
  final PrescriptionDraft draft;
  final bool isActive;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final meds = draft.validMedicines;
    final tests = draft.investigations;
    final dx = draft.primaryDiagnosis.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('dd MMM yyyy').format(draft.prescriptionDate),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                if (dx.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    dx,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                  ),
                ],
                if (meds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meds.map((m) {
                      final name = m.name.trim();
                      final dosage = m.dosageLabel.trim();
                      return dosage.isEmpty ? name : '$name $dosage';
                    }).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                  ),
                ],
                if (tests.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tests
                        .where((t) => t.name.trim().isNotEmpty)
                        .map((t) => t.name.trim())
                        .join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    'Editing',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.doctorBlue,
                    ),
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: onEdit,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.doctorBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Edit',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => PrescriptionPreviewModal.show(context, draft: draft),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.doctorBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'View',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Send To Sheet ─────────────────────────────────────────────────────────────

class _SendToSheet extends StatefulWidget {
  const _SendToSheet({required this.draft, required this.patient});
  final PrescriptionDraft draft;
  final PatientClinicalContext patient;

  @override
  State<_SendToSheet> createState() => _SendToSheetState();
}

class _SendToSheetState extends State<_SendToSheet> {
  bool _toPatient = true;
  bool _toLab = false;
  bool _toMedical = true;
  bool _sending = false;

  Future<void> _send() async {
    if (!_toPatient && !_toLab && !_toMedical) {
      AppToast.info(context, 'Please select at least one recipient');
      return;
    }
    if (!widget.draft.hasResolvedPatientId) {
      AppToast.info(context, 'This patient is not registered yet — the prescription cannot be sent.');
      return;
    }

    final doctorId = DoctorSession.loggedInDoctorId.trim();
    if (doctorId.isEmpty) {
      AppToast.info(context, 'Doctor session expired. Sign in again and retry.');
      return;
    }

    setState(() => _sending = true);

    final sentTo = <String>[];
    final warnings = <String>[];
    final doctorName = DoctorProfileStore.displayName;
    final appointmentId = widget.patient.appointmentId;

    try {
      await ClinicalPrescriptionStore.instance.save(widget.draft);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      AppToast.info(context, 'Failed to send prescription. Please check your connection and try again.');
      return;
    }

    if (_toPatient) {
      PatientProfileMock.syncPrescriptionFromDraft(widget.draft, doctorName: doctorName);
      final diagnosis = widget.draft.primaryDiagnosis.trim();
      PatientNotificationEmitter.notifyPrescriptionFromDoctor(
        doctorName: doctorName,
        prescriptionId: widget.draft.prescriptionId,
        diagnosis: diagnosis.isEmpty ? 'New prescription' : diagnosis,
      );
      if (appointmentId != null && appointmentId.isNotEmpty) {
        try {
          await SharedAppointmentsStore.instance.saveConsultationOutcome(
            recordId: appointmentId,
            diagnosis: widget.draft.primaryDiagnosis,
            hasPrescription: true,
          );
        } catch (_) {
          warnings.add('Appointment record not updated');
        }
      }
      sentTo.add('Patient');
    }

    if (_toMedical) {
      try {
        await MedicalStoreRegistry.refreshFromFirestore();
        final connections = PharmacyConnectionStore.instance.activeForDoctor(doctorId);
        if (connections.isEmpty) {
          warnings.add('No connected medical store');
        } else {
          final sent = await PharmacyPrescriptionStore.instance.sendToStores(
            draft: widget.draft,
            storeIds: connections.map((c) => c.medicalStoreId).toList(),
            doctorId: doctorId,
            doctorName: DoctorProfileStore.displayNameWithPrefix,
          );
          if (sent.isNotEmpty) {
            sentTo.add('Medical Store');
          } else {
            warnings.add('Medical store send failed');
          }
        }
      } catch (_) {
        warnings.add('Medical store send failed');
      }
    }

    if (_toLab) {
      try {
        var labTests = widget.draft.labTestNames;
        if (labTests.isEmpty) {
          labTests = widget.draft.validInvestigations
              .map((e) => e.name.trim())
              .where((name) => name.isNotEmpty)
              .toList();
        }
        if (labTests.isEmpty) {
          warnings.add('No lab tests on this prescription');
        } else {
          final connections = LabConnectionStore.instance.activeForDoctor(doctorId);
          if (connections.isEmpty) {
            warnings.add('Connect a lab first from the Labs tab');
          } else {
            for (final conn in connections) {
              await LabOrderService.sendOrder(
                patient: widget.patient,
                testIds: labTests.map((n) => 'rx_${n.hashCode.abs()}').toList(),
                testNames: labTests,
                labId: conn.labId,
                labName: conn.labName,
                source: 'prescription',
              );
            }
            sentTo.add('Lab');
          }
        }
      } catch (_) {
        warnings.add('Lab send failed');
      }
    }

    if (!mounted) return;
    setState(() => _sending = false);

    if (sentTo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            warnings.isEmpty
                ? 'Failed to send prescription. Please try again.'
                : warnings.join('. '),
          ),
        ),
      );
      return;
    }

    Navigator.pop(context);

    final label = sentTo.join(', ');
    final warningSuffix = warnings.isEmpty ? '' : ' (${warnings.join('; ')})';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Prescription sent to: $label$warningSuffix'),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.send_outlined, color: AppColors.doctorBlue),
              const SizedBox(width: 10),
              Text(
                'Send Prescription to',
                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select all recipients for ${widget.patient.patientName}\'s prescription',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 16),
          const Divider(),
          _RecipientTile(
            icon: Icons.person_outline,
            label: 'Patient',
            subtitle: 'Full prescription report (medicines, tests, advice)',
            value: _toPatient,
            onChanged: (v) => setState(() => _toPatient = v),
          ),
          _RecipientTile(
            icon: Icons.biotech_outlined,
            label: 'Lab',
            subtitle: 'Lab test orders only (no medicines)',
            value: _toLab,
            onChanged: (v) => setState(() => _toLab = v),
          ),
          _RecipientTile(
            icon: Icons.local_pharmacy_outlined,
            label: 'Medical Store',
            subtitle: 'Medicines list for dispensing only',
            value: _toMedical,
            onChanged: (v) => setState(() => _toMedical = v),
          ),
          const Divider(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_sending ? 'Sending…' : 'Send Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.doctorBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      activeColor: AppColors.doctorBlue,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.trailing,
      title: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.doctorBlue),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context))),
      ),
    );
  }
}
