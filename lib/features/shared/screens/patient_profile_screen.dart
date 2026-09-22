import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show lerpDouble;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:medibond/core/constants/app_constants.dart';
import 'package:medibond/core/constants/app_icons.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/firebase/firestore_paths.dart';
import 'package:medibond/core/firebase/firestore_service.dart';
import 'package:medibond/core/layout/responsive_layout.dart';
import 'package:medibond/core/media/gallery_image_picker.dart';
import 'package:medibond/core/notifications/app_toast.dart';
import 'package:medibond/core/session/ambulance_session.dart';
import 'package:medibond/core/session/app_session.dart';
import 'package:medibond/features/welcome/welcome_screen.dart';
import 'package:medibond/core/session/doctor_session.dart';
import 'package:medibond/core/session/patient_session.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/features/shared/screens/appointment_detail_screen.dart';
import 'package:medibond/features/doctor/clinical/data/clinical_prescription_store.dart';
import 'package:medibond/features/doctor/clinical/models/clinical_models.dart';
import 'package:medibond/features/doctor/clinical/prescription/patient_prescription_history_screen.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/doctor/patients/data/doctor_patients_service.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import 'package:medibond/features/doctor/patients/widgets/visit_history_clinical_editor.dart';
import 'package:medibond/features/doctor/widgets/doctor_ui_widgets.dart';
import 'package:medibond/features/doctor/widgets/patient_sharing_blocked_notice.dart';
import 'package:medibond/features/patient/profile/about/about_screen.dart';
import 'package:medibond/features/patient/profile/account/account_security_screen.dart';
import 'package:medibond/features/patient/profile/data/patient_photo_local_store.dart';
import 'package:medibond/features/patient/profile/data/patient_profile_mock.dart';
import 'package:medibond/features/patient/profile/edit_profile_screen.dart';
import 'package:medibond/features/patient/profile/family/add_family_member_profile_screen.dart';
import 'package:medibond/features/patient/profile/family/family_profiles_screen.dart';
import 'package:medibond/features/patient/profile/health/my_allergies_screen.dart';
import 'package:medibond/features/patient/profile/health/my_conditions_screen.dart';
import 'package:medibond/features/patient/profile/health/vaccination_records_screen.dart';
import 'package:medibond/features/patient/profile/models/patient_profile_models.dart';
import 'package:medibond/features/patient/profile/prescriptions/my_prescriptions_screen.dart';
import 'package:medibond/features/patient/profile/settings/notifications_settings_screen.dart';
import 'package:medibond/features/patient/profile/support/help_support_screen.dart';
import 'package:medibond/features/patient/profile/widgets/profile_flat_section.dart';
import 'package:medibond/features/patient/profile/widgets/profile_hero_section.dart';
import 'package:medibond/features/patient/profile/widgets/profile_menu_tile.dart';
import 'package:medibond/features/patient/profile/widgets/profile_web_layout.dart';
import 'package:medibond/features/patient/records/vitals_tracker_screen.dart';
import 'package:medibond/widgets/image_viewer_dialog.dart';
import 'package:medibond/widgets/logout_button.dart';
import '../../../core/theme/app_typography.dart';

class PatientProfileScreen extends StatelessWidget {
  const PatientProfileScreen({
    super.key,
    this.isDoctorView = false,
    this.patientId,
    this.onOpenAppointments,
    this.embeddedInShell = false,
  });

  final bool isDoctorView;
  final String? patientId;
  final VoidCallback? onOpenAppointments;
  final bool embeddedInShell;

  static Future<void> open(BuildContext context) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const PatientProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isDoctorView) {
      return _DoctorPatientProfileScreen(patientId: patientId ?? '');
    }
    return _PatientPatientProfileScreen(
      onOpenAppointments: onOpenAppointments,
      embeddedInShell: embeddedInShell,
    );
  }
}

// --- DOCTOR VIEW IMPLEMENTATION ---

class _DoctorPatientProfileScreen extends StatefulWidget {
  const _DoctorPatientProfileScreen({required this.patientId});

  final String patientId;

  @override
  State<_DoctorPatientProfileScreen> createState() =>
      _DoctorPatientProfileScreenState();
}

class _DoctorPatientProfileScreenState
    extends State<_DoctorPatientProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  PatientFileType? _fileFilter;
  DateTime? _visitFrom;
  DateTime? _visitTo;
  final _store = SharedAppointmentsStore.instance;

  DoctorPatientProfile? _profile;
  bool _loadingProfile = true;
  bool _reloading = false;
  bool _loadingMedications = true;
  bool _clinicalDataBlocked = false;
  List<MedicationRecord> _medications = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _store.addListener(_onAppointmentsChanged);
    unawaited(_reloadProfile());
    unawaited(_loadMedications());
  }

  Future<void> _reloadProfile() async {
    if (_reloading) return;
    _reloading = true;
    try {
      final profile = await DoctorPatientsService.profileFor(widget.patientId);
      final blocked = !await DoctorPatientsService.canViewClinicalHistoryForKey(
          widget.patientId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _clinicalDataBlocked = blocked;
        _loadingProfile = false;
      });
    } finally {
      _reloading = false;
    }
  }

  Future<void> _loadMedications() async {
    try {
      final medications = await DoctorPatientsService.loadMedicationsForProfile(
              widget.patientId)
          .timeout(const Duration(seconds: 10), onTimeout: () => []);
      if (!mounted) return;
      setState(() {
        _medications = medications;
      });
    } catch (_) {
      // silently ignore — show empty state
    } finally {
      if (mounted) setState(() => _loadingMedications = false);
    }
  }

  void _onAppointmentsChanged() {
    unawaited(_reloadProfile());
    if (!_loadingMedications) {
      setState(() => _loadingMedications = true);
      unawaited(_loadMedications());
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onAppointmentsChanged);
    _tabController.dispose();
    super.dispose();
  }

  List<VisitRecord> _filteredVisits(List<VisitRecord> visits) {
    return visits.where((visit) {
      final day = DateTime(visit.date.year, visit.date.month, visit.date.day);
      if (_visitFrom != null) {
        final from =
            DateTime(_visitFrom!.year, _visitFrom!.month, _visitFrom!.day);
        if (day.isBefore(from)) return false;
      }
      if (_visitTo != null) {
        final to = DateTime(_visitTo!.year, _visitTo!.month, _visitTo!.day);
        if (day.isAfter(to)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _pickVisitDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _visitFrom : _visitTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.doctorBlue),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _visitFrom = picked;
        if (_visitTo != null && picked.isAfter(_visitTo!)) {
          _visitTo = picked;
        }
      } else {
        _visitTo = picked;
        if (_visitFrom != null && picked.isBefore(_visitFrom!)) {
          _visitFrom = picked;
        }
      }
    });
  }

  void _openVisitRecord(VisitRecord visit) {
    final appointment = _store.doctorAppointmentForTarget(
      visit.id,
      DoctorSession.loggedInDoctorId,
    );
    if (appointment == null) {
      AppToast.info(context, 'Visit record not found');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentDetailScreen(appointment: appointment),
      ),
    );
  }

  void _openPrescriptionHistory(DoctorPatientProfile profile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientPrescriptionHistoryScreen(
          patient: PatientClinicalContext(
            patientName: profile.summary.name,
            age: profile.summary.age,
            gender: profile.summary.gender,
            patientId: profile.summary.id,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return Scaffold(
        appBar: AppBar(title: const Text('Patient Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _profile;
    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Patient Profile')),
        body: const Center(child: Text('Patient not found')),
      );
    }

    final s = profile.summary;

    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      appBar: AppBar(
        title: Text(s.name),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.doctorBlue,
          unselectedLabelColor: AppColors.textSecondaryOf(context),
          indicatorColor: AppColors.doctorBlue,
          labelStyle: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Personal Info'),
            Tab(text: 'Medical History'),
            Tab(text: 'Visit History'),
            Tab(text: 'Reports & Files'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: ResponsiveLayout.contentMaxWidth(context)),
          child: TabBarView(
            controller: _tabController,
            children: [
              _PersonalInfoTab(profile: profile),
              _MedicalHistoryTab(
                profile: profile,
                medications: _medications,
                loadingMedications: _loadingMedications,
                clinicalDataBlocked: _clinicalDataBlocked,
              ),
              _VisitHistoryTab(
                visits: _filteredVisits(profile.visits),
                clinicalDataBlocked: _clinicalDataBlocked,
                visitFrom: _visitFrom,
                visitTo: _visitTo,
                onPickFrom: () => _pickVisitDate(isFrom: true),
                onPickTo: () => _pickVisitDate(isFrom: false),
                onClearDates: () => setState(() {
                  _visitFrom = null;
                  _visitTo = null;
                }),
                onViewRecord: _openVisitRecord,
                onViewPrescription: () => _openPrescriptionHistory(profile),
              ),
              _ReportsTab(
                profile: profile,
                clinicalDataBlocked: _clinicalDataBlocked,
                fileFilter: _fileFilter,
                onFilterChanged: (f) => setState(() => _fileFilter = f),
                onOpenPrescriptions: () => _openPrescriptionHistory(profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonalInfoTab extends StatelessWidget {
  const _PersonalInfoTab({required this.profile});

  final DoctorPatientProfile profile;

  @override
  Widget build(BuildContext context) {
    final s = profile.summary;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              PatientAvatar(name: s.name, gender: s.gender),
              const SizedBox(height: 8),
              Text(s.name,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _InfoCard(title: 'Basic Details', rows: [
          _Row('Age', '${s.age} years'),
          _Row('Gender', AppConstants.patientGenderLabel(s.gender)),
          _Row('DOB', DateFormat('dd MMM yyyy').format(profile.dateOfBirth)),
          _Row('Blood group', profile.bloodGroup),
        ]),
        _InfoCard(title: 'Contact', rows: [
          _Row('Mobile', s.mobile),
          _Row('Email', profile.email),
        ]),
        _InfoCard(title: 'Emergency Contact', rows: [
          _Row('Name', profile.emergencyContact.name),
          _Row('Phone', profile.emergencyContact.phone),
        ]),
        _InfoCard(title: 'Insurance', rows: [
          _Row('Provider', profile.insurance.provider),
          _Row('Policy no.', profile.insurance.policyNumber),
        ]),
      ],
    );
  }
}

DateTime? _latestPrescriptionDateForMedicine(
    String patientKey, String medicineName) {
  final key = medicineName.trim().toLowerCase();
  if (key.isEmpty) return null;

  DateTime? latest;
  for (final rx in ClinicalPrescriptionStore.instance.forPatient(patientKey)) {
    for (final medicine in rx.validMedicines) {
      if (medicine.name.trim().toLowerCase() != key) continue;
      if (latest == null || rx.prescriptionDate.isAfter(latest)) {
        latest = rx.prescriptionDate;
      }
    }
  }
  return latest;
}

class _MedicalHistoryTab extends StatelessWidget {
  const _MedicalHistoryTab({
    required this.profile,
    required this.medications,
    required this.loadingMedications,
    required this.clinicalDataBlocked,
  });

  final DoctorPatientProfile profile;
  final List<MedicationRecord> medications;
  final bool loadingMedications;
  final bool clinicalDataBlocked;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (clinicalDataBlocked) ...[
          const PatientSharingBlockedNotice(compact: true),
          const SizedBox(height: 16),
        ],
        _SectionCard(
          title: 'Known Conditions',
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: profile.knownConditions.isEmpty
                ? [
                    Text('None recorded',
                        style: GoogleFonts.inter(
                            color: AppColors.textSecondaryOf(context)))
                  ]
                : profile.knownConditions
                    .map((c) =>
                        StatusBadge(label: c, color: AppColors.doctorBlue))
                    .toList(),
          ),
        ),
        _SectionCard(
          title: 'Known Allergies',
          child: Column(
            children: profile.allergies.map((a) {
              final color = switch (a.severity) {
                'Severe' => const Color(0xFFDC2626),
                'Moderate' => const Color(0xFFEA580C),
                _ => const Color(0xFF2563EB),
              };
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(a.name),
                trailing: StatusBadge(label: a.severity, color: color),
              );
            }).toList(),
          ),
        ),
        _SectionCard(
          title: 'Past Surgeries',
          child: Column(
            children: profile.surgeries.map((s) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.medical_services_outlined,
                    color: AppColors.doctorBlue, size: 20),
                title: Text(s.procedure,
                    style:
                        GoogleFonts.inter(fontSize: AppTypography.bodyMedium)),
                subtitle: Text(DateFormat('dd MMM yyyy').format(s.date)),
              );
            }).toList(),
          ),
        ),
        _SectionCard(
          title: 'Family History',
          child: Text(profile.familyHistory,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium, height: 1.4)),
        ),
        _SectionCard(
          title: 'Current Medications',
          child: loadingMedications
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : medications.isEmpty
                  ? Text(
                      clinicalDataBlocked
                          ? 'Medication history is hidden while sharing is off.'
                          : 'No medications prescribed yet',
                      style: GoogleFonts.inter(
                          color: AppColors.textSecondaryOf(context)),
                    )
                  : Column(
                      children: medications.map((m) {
                        final prescribedOn = _latestPrescriptionDateForMedicine(
                          profile.summary.id,
                          m.name,
                        );
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            AppIcons.prescription,
                            color: AppColors.doctorBlue,
                            size: 20,
                          ),
                          title: Text(
                            m.name,
                            style:
                                GoogleFonts.inter(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.dosage,
                                  style: GoogleFonts.inter(
                                      fontSize: AppTypography.bodySmall)),
                              if (prescribedOn != null)
                                Text(
                                  'Prescribed ${DateFormat('dd MMM yyyy').format(prescribedOn)}',
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.labelSmall,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
        ),
        _SectionCard(
          title: 'Vaccination Records',
          child: Column(
            children: profile.vaccinations.map((v) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.vaccines_outlined,
                    color: AppColors.doctorBlue, size: 20),
                title: Text(v.name),
                subtitle: Text(DateFormat('dd MMM yyyy').format(v.date)),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _VisitHistoryTab extends StatelessWidget {
  const _VisitHistoryTab({
    required this.visits,
    required this.clinicalDataBlocked,
    required this.visitFrom,
    required this.visitTo,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClearDates,
    required this.onViewRecord,
    required this.onViewPrescription,
  });

  final List<VisitRecord> visits;
  final bool clinicalDataBlocked;
  final DateTime? visitFrom;
  final DateTime? visitTo;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onClearDates;
  final ValueChanged<VisitRecord> onViewRecord;
  final VoidCallback onViewPrescription;

  String _statusLabel(AppointmentStatus? status) => switch (status) {
        AppointmentStatus.completed => 'Completed',
        AppointmentStatus.confirmed => 'Confirmed',
        AppointmentStatus.inProgress => 'In progress',
        AppointmentStatus.pendingRequest => 'Pending',
        AppointmentStatus.cancelled => 'Cancelled',
        AppointmentStatus.noShow => 'No show',
        AppointmentStatus.waiting => 'Waiting',
        null => 'Scheduled',
      };

  @override
  Widget build(BuildContext context) {
    if (clinicalDataBlocked) {
      return const PatientSharingBlockedEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 16),
                label: Text(
                  visitFrom == null
                      ? 'From date'
                      : DateFormat('dd MMM yyyy').format(visitFrom!),
                ),
                onPressed: onPickFrom,
              ),
              ActionChip(
                avatar: const Icon(Icons.event, size: 16),
                label: Text(
                  visitTo == null
                      ? 'To date'
                      : DateFormat('dd MMM yyyy').format(visitTo!),
                ),
                onPressed: onPickTo,
              ),
              if (visitFrom != null || visitTo != null)
                TextButton(onPressed: onClearDates, child: const Text('Clear')),
            ],
          ),
        ),
        Expanded(
          child: visits.isEmpty
              ? Center(
                  child: Text(
                    'No visits in this date range',
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondaryOf(context)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: visits.length,
                  itemBuilder: (context, index) {
                    final v = visits[index];
                    final isLast = index == visits.length - 1;
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: const BoxDecoration(
                                  color: AppColors.doctorBlue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (!isLast)
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    color: AppColors.borderOf(context),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.cardBgOf(context),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.cardRadius),
                                border: Border.all(
                                    color: AppColors.borderOf(context)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('dd MMM yyyy').format(v.date),
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.labelMedium,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.doctorBlue,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    v.diagnosis,
                                    style: GoogleFonts.inter(
                                        fontSize: AppTypography.bodyMedium,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 10),
                                  VisitHistoryClinicalEditor(
                                    initialChiefComplaints: v.chiefComplaints,
                                    initialObservations: v.observations,
                                  ),
                                  const SizedBox(height: 6),
                                  StatusBadge(
                                    label: _statusLabel(v.status),
                                    color:
                                        v.status == AppointmentStatus.completed
                                            ? const Color(0xFF16A34A)
                                            : AppColors.doctorBlue,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (v.hasPrescription)
                                        TextButton.icon(
                                          onPressed: onViewPrescription,
                                          icon: const Icon(
                                              AppIcons.prescription,
                                              size: 16),
                                          label: const Text('Prescription'),
                                        ),
                                      if (v.hasLabReports)
                                        TextButton.icon(
                                          onPressed: () => onViewRecord(v),
                                          icon: const Icon(
                                              Icons.biotech_outlined,
                                              size: 16),
                                          label: const Text('Lab Reports'),
                                        ),
                                    ],
                                  ),
                                  OutlinedButton(
                                    onPressed: () => onViewRecord(v),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.doctorBlue,
                                      side: const BorderSide(
                                          color: AppColors.doctorBlue),
                                      minimumSize:
                                          const Size(double.infinity, 34),
                                    ),
                                    child: const Text('View Full Record'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab({
    required this.profile,
    required this.clinicalDataBlocked,
    required this.fileFilter,
    required this.onFilterChanged,
    required this.onOpenPrescriptions,
  });

  final DoctorPatientProfile profile;
  final bool clinicalDataBlocked;
  final PatientFileType? fileFilter;
  final ValueChanged<PatientFileType?> onFilterChanged;
  final VoidCallback onOpenPrescriptions;

  String _typeLabel(PatientFileType t) => switch (t) {
        PatientFileType.prescription => 'Prescription',
        PatientFileType.labReport => 'Lab Report',
        PatientFileType.imaging => 'Imaging',
        PatientFileType.dischargeSummary => 'Discharge Summary',
      };

  @override
  Widget build(BuildContext context) {
    final files = fileFilter == null
        ? profile.files
        : profile.files.where((f) => f.type == fileFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All'),
                selected: fileFilter == null,
                onSelected: (_) => onFilterChanged(null),
                selectedColor: AppColors.doctorBlue.withValues(alpha: 0.15),
                checkmarkColor: AppColors.doctorBlue,
              ),
              ...PatientFileType.values.map((t) {
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: FilterChip(
                    label: Text(_typeLabel(t),
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall)),
                    selected: fileFilter == t,
                    onSelected: (_) => onFilterChanged(t),
                    selectedColor: AppColors.doctorBlue.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.doctorBlue,
                  ),
                );
              }),
            ],
          ),
        ),
        Expanded(
          child: clinicalDataBlocked && files.isEmpty
              ? const PatientSharingBlockedEmptyState()
              : files.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('No documents yet',
                              style: GoogleFonts.inter(
                                  color: AppColors.textSecondaryOf(context))),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: onOpenPrescriptions,
                            child: const Text('View prescription history'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final f = files[index];
                        return ListTile(
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppConstants.inputRadius),
                            side:
                                BorderSide(color: AppColors.borderOf(context)),
                          ),
                          leading: Icon(
                            f.type == PatientFileType.imaging
                                ? Icons.image_outlined
                                : Icons.insert_drive_file_outlined,
                            color: AppColors.doctorBlue,
                          ),
                          title: Text(f.name,
                              style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodySmall)),
                          subtitle: Text(
                            '${_typeLabel(f.type)} · ${DateFormat('dd MMM yyyy').format(f.date)}',
                            style: GoogleFonts.inter(
                                fontSize: AppTypography.labelSmall),
                          ),
                          trailing: IconButton(
                            icon:
                                const Icon(Icons.visibility_outlined, size: 20),
                            onPressed: onOpenPrescriptions,
                          ),
                          onTap: onOpenPrescriptions,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows});

  final String title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context)))),
          Expanded(
              child: Text(value,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PatientProfileHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PatientProfileHeaderDelegate({
    required this.profile,
    required this.photoUrl,
    required this.localPhotoBytes,
    required this.onPickPhoto,
    required this.topPadding,
    required this.onBack,
    this.showBackButton = true,
  });

  final PatientProfile profile;
  final String? photoUrl;
  final Uint8List? localPhotoBytes;
  final VoidCallback onPickPhoto;
  final double topPadding;
  final VoidCallback onBack;
  final bool showBackButton;

  static const double _collapsedHeight = 56.0;
  static const double _expandedContentHeight = 216.0;

  @override
  double get minExtent => topPadding + _collapsedHeight;

  @override
  double get maxExtent => topPadding + _expandedContentHeight;

  @override
  bool shouldRebuild(covariant _PatientProfileHeaderDelegate oldDelegate) {
    return oldDelegate.profile != profile ||
        oldDelegate.photoUrl != photoUrl ||
        oldDelegate.localPhotoBytes != localPhotoBytes ||
        oldDelegate.topPadding != topPadding;
  }

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final scrollRange = (maxExtent - minExtent).clamp(1.0, double.infinity);
    final progress = (shrinkOffset / scrollRange).clamp(0.0, 1.0);

    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final border = AppColors.borderOf(context);

    // Dynamic interpolated values
    final titleOpacity = (1.0 - progress * 2.5).clamp(0.0, 1.0);
    final titleDy = -12.0 * progress;

    final avatarRadius = lerpDouble(38.0, 18.0, progress)!;
    final avatarPadding = lerpDouble(3.0, 2.0, progress)!;
    final avatarLeft = lerpDouble(16.0, 52.0, progress)!;
    final avatarTop =
        lerpDouble(topPadding + 104.0, topPadding + 8.0, progress)!;
    final cameraOpacity = (1.0 - progress * 3.2).clamp(0.0, 1.0);

    final nameLeft = lerpDouble(108.0, 100.0, progress)!;
    final nameTop =
        lerpDouble(topPadding + 106.0, topPadding + 18.0, progress)!;
    final nameFontSize = lerpDouble(20.0, 16.0, progress)!;
    final nameFontWeight =
        FontWeight.lerp(FontWeight.w700, FontWeight.w600, progress)!;

    final metaDetailsOpacity = (1.0 - progress * 2.2).clamp(0.0, 1.0);

    final displayName =
        profile.name.trim().isNotEmpty ? profile.name.trim() : 'Profile';

    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scaffoldBg,
          border: Border(
            bottom: BorderSide(
              color: border.withValues(alpha: 0.25 * progress),
              width: 1,
            ),
          ),
          boxShadow: progress > 0.6
              ? [
                  BoxShadow(
                    color: textPrimary.withValues(alpha: 0.04 * progress),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showBackButton)
                Positioned(
                  top: topPadding + 6.0,
                  left: 4.0,
                  width: 44.0,
                  height: 44.0,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: textPrimary,
                    onPressed: onBack,
                    tooltip: 'Back',
                  ),
                ),

              // 2. Expanded Title & Subtitle ("Profile" / "Your account & health")
              if (titleOpacity > 0.01)
                Positioned(
                  top: topPadding + 44.0 + titleDy,
                  left: 16.0,
                  right: 16.0,
                  child: Opacity(
                    opacity: titleOpacity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Profile',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.headlineLarge,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Your account & health',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            color: textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 3. Avatar (lerps from large to small, and slides into pinned top bar)
              Positioned(
                top: avatarTop,
                left: avatarLeft,
                child: _buildAvatar(
                  context,
                  radius: avatarRadius,
                  padding: avatarPadding,
                  cameraOpacity: cameraOpacity,
                ),
              ),

              // 4. Name text (lerps from large next to avatar to pinned top bar next to small avatar)
              Positioned(
                top: nameTop,
                left: nameLeft,
                right: 16.0,
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: nameFontSize,
                    fontWeight: nameFontWeight,
                    color: textPrimary,
                    height: 1.15,
                  ),
                ),
              ),

              // 5. Expanded Meta Details (chips, phone, email)
              if (metaDetailsOpacity > 0.01)
                Positioned(
                  top: topPadding + 132.0,
                  left: 108.0,
                  right: 16.0,
                  child: Opacity(
                    opacity: metaDetailsOpacity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (profile.age > 0 ||
                            profile.gender.trim().isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (profile.age > 0)
                                MetaChip('${profile.age} yrs'),
                              if (profile.gender.trim().isNotEmpty)
                                MetaChip(profile.gender),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (profile.mobile.trim().isNotEmpty) ...[
                          MetaLine(
                              icon: Icons.phone_outlined, text: profile.mobile),
                          const SizedBox(height: 4),
                        ],
                        if (profile.email.trim().isNotEmpty) ...[
                          MetaLine(
                              icon: Icons.mail_outline, text: profile.email),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(
    BuildContext context, {
    required double radius,
    required double padding,
    required double cameraOpacity,
  }) {
    final initial = (profile.photoInitial ??
            (profile.name.isNotEmpty ? profile.name[0] : 'P'))
        .toUpperCase();
    final hasLocalPhoto =
        localPhotoBytes != null && localPhotoBytes!.isNotEmpty;
    final hasNetworkPhoto =
        !hasLocalPhoto && photoUrl != null && photoUrl!.isNotEmpty;

    ImageProvider? avatarImage;
    if (hasLocalPhoto) {
      avatarImage = MemoryImage(localPhotoBytes!);
    } else if (hasNetworkPhoto) {
      avatarImage = NetworkImage(photoUrl!);
    }

    final fontSize = radius * 0.74;

    return GestureDetector(
      onTap: onPickPhoto,
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D9488), Color(0xFF0369A1)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.patientTeal.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: radius,
              backgroundColor: AppColors.surfaceOf(context),
              backgroundImage: avatarImage,
              child: avatarImage == null
                  ? Text(
                      initial,
                      style: GoogleFonts.inter(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w800,
                        color: AppColors.patientTeal,
                      ),
                    )
                  : null,
            ),
            if (cameraOpacity > 0.05)
              Positioned(
                right: -1,
                bottom: -1,
                child: Opacity(
                  opacity: cameraOpacity,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.patientTeal,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.surfaceOf(context), width: 2),
                    ),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      size: 13,
                      color: AppColors.surfaceOf(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- PATIENT VIEW IMPLEMENTATION ---

class _PatientPatientProfileScreen extends StatefulWidget {
  const _PatientPatientProfileScreen({
    this.onOpenAppointments,
    this.embeddedInShell = false,
  });

  final VoidCallback? onOpenAppointments;
  final bool embeddedInShell;

  @override
  State<_PatientPatientProfileScreen> createState() =>
      _PatientPatientProfileScreenState();
}

class _PatientPatientProfileScreenState
    extends State<_PatientPatientProfileScreen> {
  String? _photoUrl;
  Uint8List? _localPhotoBytes;

  String _effectivePatientId() {
    if (PatientSession.loggedInPatientId.isNotEmpty) {
      return PatientSession.loggedInPatientId;
    }
    if (FirebaseBootstrap.isReady) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.uid.isNotEmpty) {
          return user.uid;
        }
      } catch (_) {}
    }
    return AppSession.patientId;
  }

  @override
  void initState() {
    super.initState();
    _photoUrl = PatientProfileMock.profile.photoUrl;
    _loadLocalPhoto();
    _loadProfilePhotoUrl();
    PatientProfileMock.listenable.addListener(_refresh);
  }

  @override
  void dispose() {
    PatientProfileMock.listenable.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _loadLocalPhoto() async {
    final patientId = _effectivePatientId();
    if (patientId.isEmpty) return;

    final bytes = await PatientPhotoLocalStore.load(patientId);
    if (!mounted || bytes == null) return;
    setState(() => _localPhotoBytes = bytes);
  }

  Future<void> _loadProfilePhotoUrl() async {
    final patientId = _effectivePatientId();
    if (patientId.isEmpty || !FirebaseBootstrap.isReady) return;

    try {
      final data = await FirestoreService.instance.patientProfile
          .fetchPatientDocument(patientId);
      final url =
          (data?['photoUrl'] as String?) ?? (data?['photoURL'] as String?);
      if (!mounted) return;
      final resolvedUrl = (url != null && url.isNotEmpty) ? url : null;
      setState(() {
        _photoUrl = resolvedUrl;
        PatientProfileMock.profile.photoUrl = resolvedUrl;
      });
    } catch (_) {}
  }

  Future<void> _pickPhoto() async {
    final photoUrl = _photoUrl ?? PatientProfileMock.profile.photoUrl;
    final localBytes = _localPhotoBytes ??
        PatientPhotoLocalStore.readCached(_effectivePatientId());
    final hasLocalPhoto = localBytes != null && localBytes.isNotEmpty;
    final hasNetworkPhoto =
        !hasLocalPhoto && photoUrl != null && photoUrl.isNotEmpty;

    ImageProvider? currentImage;
    if (hasLocalPhoto) {
      currentImage = MemoryImage(localBytes);
    } else if (hasNetworkPhoto) {
      currentImage = NetworkImage(photoUrl);
    }

    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentImage != null)
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: const Text('View Photo'),
                onTap: () => Navigator.pop(ctx, 'view'),
              ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (currentImage != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('Remove Photo',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w500)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    if (source == 'view') {
      if (currentImage != null) {
        showImageViewerDialog(context, currentImage, title: 'Profile Photo');
      }
      return;
    }

    if (source == 'remove') {
      final patientId = _effectivePatientId();
      if (patientId.isNotEmpty) {
        await PatientPhotoLocalStore.clear(patientId);
        if (FirebaseBootstrap.isReady) {
          try {
            await FirestoreService.instance.patientProfile.savePatientDocument(
              patientId,
              {
                'hasLocalPhoto': false,
                'photoStorage': null,
                'photoUrl': FieldValue.delete(),
                'photoURL': FieldValue.delete(),
              },
            );
          } catch (_) {}
          try {
            await FirebaseFirestore.instance
                .collection(FirestorePaths.users)
                .doc(patientId)
                .set({
              'photoUrl': FieldValue.delete(),
              'photoURL': FieldValue.delete(),
            }, SetOptions(merge: true));
          } catch (_) {}
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await user.updatePhotoURL(null);
              await user.reload();
            }
          } catch (_) {}
        }
      }
      if (!mounted) return;
      setState(() {
        _localPhotoBytes = null;
        _photoUrl = null;
        PatientProfileMock.profile.photoUrl = null;
      });
      PatientProfileMock.notifyProfileUpdated();
      return;
    }

    final picked = source == 'camera'
        ? await GalleryImagePicker.pickFromCamera()
        : await GalleryImagePicker.pickSingle();
    if (picked == null || !mounted) return;

    final platformFile = PlatformFile(
      name: picked.name,
      size: picked.bytes.length,
      path: picked.path,
      bytes: picked.bytes,
    );

    await _uploadProfilePhoto(platformFile);
  }

  Future<void> _uploadProfilePhoto(PlatformFile file) async {
    final patientId = _effectivePatientId();
    if (patientId.isEmpty) {
      if (!mounted) return;
      AppToast.info(context, 'Please log in to set a profile photo');
      return;
    }

    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && !kIsWeb && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      AppToast.info(context, 'Failed to read photo');
      return;
    }

    if (bytes.length > PatientPhotoLocalStore.maxFileBytes) {
      if (!mounted) return;
      AppToast.info(context, 'Photo must be 5 MB or smaller');
      return;
    }

    // 1. Immediately cache locally for instant UI update
    await PatientPhotoLocalStore.save(patientId, bytes);
    if (mounted) {
      setState(() {
        _localPhotoBytes = bytes;
      });
    }

    try {
      // 2. Upload to Firebase Storage
      String? remoteUrl;
      if (FirebaseBootstrap.isReady) {
        try {
          remoteUrl = await PatientPhotoLocalStore.uploadToFirebaseStorage(
              patientId, bytes);
        } catch (e) {
          if (kDebugMode)
            debugPrint('[PatientProfile] Storage upload warning: $e');
        }
      }

      // Fallback to Base64 data URL if storage upload failed
      final finalUrl =
          remoteUrl ?? 'data:image/jpeg;base64,${base64Encode(bytes)}';

      // 3. Save to Firestore in patients & users collections
      if (FirebaseBootstrap.isReady) {
        try {
          await FirestoreService.instance.patientProfile.savePatientDocument(
            patientId,
            {
              'hasLocalPhoto': true,
              'photoStorage': remoteUrl != null ? 'firebase' : 'base64',
              'photoUrl': remoteUrl ?? finalUrl,
              'photoURL': remoteUrl ?? finalUrl,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        } catch (e) {
          if (kDebugMode)
            debugPrint('[PatientProfile] Firestore patient doc save error: $e');
        }

        try {
          await FirebaseFirestore.instance
              .collection(FirestorePaths.users)
              .doc(patientId)
              .set({
            'photoUrl': remoteUrl ?? finalUrl,
            'photoURL': remoteUrl ?? finalUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}

        // Update Firebase Auth user photoURL if available
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null && remoteUrl != null) {
            await user.updatePhotoURL(remoteUrl);
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _localPhotoBytes = bytes;
        _photoUrl = remoteUrl ?? finalUrl;
        PatientProfileMock.profile.photoUrl = remoteUrl ?? finalUrl;
      });
      PatientProfileMock.notifyProfileUpdated();
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      AppToast.info(context, 'Failed to save photo: $e');
    }
  }

  Widget _buildProfileAvatar(PatientProfile p, {double radius = 38}) {
    final initial =
        (p.photoInitial ?? (p.name.isNotEmpty ? p.name[0] : 'P')).toUpperCase();
    final photoUrl = _photoUrl ?? PatientProfileMock.profile.photoUrl;
    final localBytes = _localPhotoBytes ??
        PatientPhotoLocalStore.readCached(_effectivePatientId());
    final hasLocalPhoto = localBytes != null && localBytes.isNotEmpty;
    final hasNetworkPhoto =
        !hasLocalPhoto && photoUrl != null && photoUrl.isNotEmpty;

    ImageProvider? avatarImage;
    if (hasLocalPhoto) {
      avatarImage = MemoryImage(localBytes);
    } else if (hasNetworkPhoto) {
      avatarImage = NetworkImage(photoUrl);
    }

    final fontSize = radius * 0.74;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D9488), Color(0xFF0369A1)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.patientTeal.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.surfaceOf(context),
            backgroundImage: avatarImage,
            child: avatarImage == null
                ? Text(
                    initial,
                    style: GoogleFonts.inter(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      color: AppColors.patientTeal,
                    ),
                  )
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.all(radius > 40 ? 6 : 5),
              decoration: BoxDecoration(
                color: AppColors.patientTeal,
                shape: BoxShape.circle,
                border:
                    Border.all(color: AppColors.surfaceOf(context), width: 2),
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: radius > 40 ? 16 : 14,
                color: AppColors.surfaceOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditProfile(PatientProfile p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(profile: p, onSaved: _refresh),
      ),
    );
    _refresh();
  }

  Future<void> _openFamilyMember(FamilyProfileMember member) async {
    final updated = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => AddFamilyMemberProfileScreen(existingMember: member),
      ),
    );
    if (updated != null) _refresh();
  }

  Future<void> _openAddFamily() async {
    final added = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(builder: (_) => const AddFamilyMemberProfileScreen()),
    );
    if (added != null) _refresh();
  }

  void _openManageFamily() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => FamilyProfilesScreen(onChanged: _refresh)),
    );
  }

  List<ProfileWebActionData> _healthWebActions() => [
        ProfileWebActionData(
          icon: Icons.healing_outlined,
          label: 'My Conditions',
          subtitle: 'Track diagnoses & history',
          iconGradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MyConditionsScreen(onChanged: _refresh)),
          ),
        ),
        ProfileWebActionData(
          icon: Icons.coronavirus_outlined,
          label: 'My Allergies',
          subtitle: 'Drug & food sensitivities',
          iconGradient: const [Color(0xFFEA580C), Color(0xFFC2410C)],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MyAllergiesScreen(onChanged: _refresh)),
          ),
        ),
        ProfileWebActionData(
          icon: Icons.vaccines_outlined,
          label: 'Vaccination Records',
          subtitle: 'Immunization history',
          iconGradient: const [Color(0xFF16A34A), Color(0xFF15803D)],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VaccinationRecordsScreen()),
          ),
        ),
        ProfileWebActionData(
          icon: Icons.monitor_heart_outlined,
          label: 'Vitals Tracker',
          subtitle: 'BP, glucose, weight & more',
          iconGradient: const [Color(0xFF0D9488), Color(0xFF0F766E)],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VitalsTrackerScreen()),
          ),
        ),
      ];

  List<ProfileWebActionData> _careWebActions() => [
        ProfileWebActionData(
          icon: AppIcons.prescription,
          label: 'My Prescriptions',
          subtitle: 'Active & past medicines',
          iconGradient: const [Color(0xFF0891B2), Color(0xFF0E7490)],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyPrescriptionsScreen()),
          ),
        ),
      ];

  List<ProfileWebActionData> _settingsWebActions() => [
        ProfileWebActionData(
          icon: Icons.notifications_outlined,
          label: 'Notifications',
          subtitle: 'Alerts & reminders',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationsSettingsScreen(onChanged: _refresh),
            ),
          ),
        ),
        ProfileWebActionData(
          icon: Icons.help_outline,
          label: 'Help & Support',
          subtitle: 'Tickets & FAQs',
          iconGradient: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
          ),
        ),
        ProfileWebActionData(
          icon: Icons.lock_outline,
          label: 'Account & Security',
          subtitle: 'Password & privacy',
          iconGradient: const [Color(0xFF475569), Color(0xFF334155)],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AccountSecurityScreen(onChanged: _refresh)),
          ),
        ),
        ProfileWebActionData(
          icon: Icons.info_outline,
          label: 'About',
          subtitle: 'App version & legal',
          iconGradient: const [Color(0xFF64748B), Color(0xFF475569)],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AboutScreen()),
          ),
        ),
        ProfileWebActionData(
          icon: Icons.person_remove_outlined,
          label: 'Delete Account',
          subtitle: 'Permanently remove data',
          iconGradient: const [Color(0xFFEF4444), Color(0xFFB91C1C)],
          onTap: () => _confirmDeleteAccount(context),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final p = PatientProfileMock.profile;
    final family = PatientProfileMock.familyMembers;
    final maxWidth = ResponsiveLayout.contentMaxWidth(context);
    final isCompact = ResponsiveLayout.isCompact(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _PatientProfileHeaderDelegate(
                  profile: p,
                  photoUrl: _photoUrl,
                  localPhotoBytes: _localPhotoBytes,
                  onPickPhoto: _pickPhoto,
                  topPadding: MediaQuery.paddingOf(context).top,
                  onBack: () => Navigator.maybePop(context),
                  showBackButton: !widget.embeddedInShell,
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.height > 0 && p.weight > 0) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: PatientBmiCard(
                          heightCm: p.height,
                          weightKg: p.weight,
                          isWide: !isCompact,
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: EditProfileButton(
                        onEdit: () => _openEditProfile(p),
                        compact: true,
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color:
                          AppColors.borderOf(context).withValues(alpha: 0.25),
                    ),
                    ProfileFlatSection(
                      shaded: true,
                      title: 'Family Profiles',
                      subtitle: 'Manage care for your loved ones',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 108,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              children: [
                                ...family.map(
                                  (m) => _FamilyChip(
                                    member: m,
                                    onTap: () => _openFamilyMember(m),
                                  ),
                                ),
                                _AddFamilyCard(onTap: _openAddFamily),
                              ],
                            ),
                          ),
                          ProfileMenuTile(
                            icon: Icons.groups_outlined,
                            label: 'Manage family profiles',
                            iconGradient: const [
                              Color(0xFF7C3AED),
                              Color(0xFF6D28D9),
                            ],
                            onTap: _openManageFamily,
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color:
                          AppColors.borderOf(context).withValues(alpha: 0.25),
                    ),
                    _buildHealthSection(),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color:
                          AppColors.borderOf(context).withValues(alpha: 0.25),
                    ),
                    _buildCareSection(),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color:
                          AppColors.borderOf(context).withValues(alpha: 0.25),
                    ),
                    _buildSettingsSection(shaded: false),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                      child: Center(child: LogoutTextButton()),
                    ),
                    SizedBox(height: isCompact ? 80 : 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthSection() {
    return ProfileFlatSection(
      shaded: false,
      title: 'My Health',
      subtitle: 'Conditions, allergies, vaccines & vitals',
      child: Column(
        children: [
          ProfileMenuTile(
            icon: Icons.healing_outlined,
            label: 'My Conditions',
            iconGradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MyConditionsScreen(onChanged: _refresh)),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.coronavirus_outlined,
            label: 'My Allergies',
            iconGradient: const [Color(0xFFEA580C), Color(0xFFC2410C)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MyAllergiesScreen(onChanged: _refresh)),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.vaccines_outlined,
            label: 'Vaccination Records',
            iconGradient: const [Color(0xFF16A34A), Color(0xFF15803D)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const VaccinationRecordsScreen()),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.monitor_heart_outlined,
            label: 'Vitals Tracker',
            iconGradient: const [Color(0xFF0D9488), Color(0xFF0F766E)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VitalsTrackerScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCareSection() {
    final shaded = ResponsiveLayout.isCompact(context);
    return ProfileFlatSection(
      shaded: shaded,
      title: 'Care',
      subtitle: 'Prescriptions & medical documents',
      child: ProfileMenuTile(
        icon: AppIcons.prescription,
        label: 'My Prescriptions',
        iconGradient: const [Color(0xFF0891B2), Color(0xFF0E7490)],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyPrescriptionsScreen()),
        ),
      ),
    );
  }

  Widget _buildSettingsSection({required bool shaded}) {
    return ProfileFlatSection(
      shaded: shaded,
      title: 'Settings',
      subtitle: 'Notifications, security & support',
      child: Column(
        children: [
          ProfileMenuTile(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    NotificationsSettingsScreen(onChanged: _refresh),
              ),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.help_outline,
            label: 'Help & Support',
            iconGradient: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.lock_outline,
            label: 'Account & Security',
            iconGradient: const [Color(0xFF475569), Color(0xFF334155)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AccountSecurityScreen(onChanged: _refresh)),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.info_outline,
            label: 'About',
            iconGradient: const [Color(0xFF64748B), Color(0xFF475569)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.person_remove_outlined,
            label: 'Delete Account',
            iconGradient: const [Color(0xFFEF4444), Color(0xFFB91C1C)],
            onTap: () => _confirmDeleteAccount(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
            'Are you sure you want to permanently delete your account and all associated data? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirestoreService.instance.user.deleteAccount(user: user);
      }
      if (!context.mounted) return;
      Navigator.of(context).pop();
      await AmbulanceSession.clear();
      AppSession.clear();
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final message = e is FirebaseFunctionsException
          ? (e.message ?? 'Could not delete account. Please try again.')
          : 'Failed to delete account. Please try again.';
      AppToast.info(context, message);
    }
  }
}

class _FamilyChip extends StatelessWidget {
  const _FamilyChip({required this.member, required this.onTap});
  final FamilyProfileMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final initial =
        (m.photoInitial ?? (m.name.isNotEmpty ? m.name[0] : 'F')).toUpperCase();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 84,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.cardBgOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                ),
                shape: BoxShape.circle,
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.surfaceOf(context),
                child: Text(
                  initial,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF7C3AED),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              m.name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w700),
            ),
            Text(
              m.relationLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 9.5, color: AppColors.textSecondaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddFamilyCard extends StatelessWidget {
  const _AddFamilyCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 84,
        decoration: BoxDecoration(
          color: AppColors.patientTeal.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: AppColors.patientTeal.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.patientTeal.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.add, color: AppColors.patientTeal, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              'Add',
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelSmall,
                fontWeight: FontWeight.w700,
                color: AppColors.patientTeal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
