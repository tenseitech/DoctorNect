import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:medibond/core/constants/ambulance_icons.dart';
import 'package:medibond/core/constants/app_constants.dart';
import 'package:medibond/core/constants/app_icons.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/core/firebase/firebase_error_messages.dart';
import 'package:medibond/core/firebase/firestore_service.dart';
import 'package:medibond/core/layout/responsive_layout.dart';
import 'package:medibond/core/notifications/app_toast.dart';
import 'package:medibond/core/notifications/doctor_notification_emitter.dart';
import 'package:medibond/core/session/doctor_session.dart';
import 'package:medibond/core/session/patient_session.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/features/ambulance/ambulance_booking_screen.dart';
import 'package:medibond/features/ambulance/models/ambulance_models.dart';
import 'package:medibond/features/doctor/appointments/appointment_actions.dart';
import 'package:medibond/features/doctor/appointments/appointment_utils.dart';
import 'package:medibond/features/doctor/appointments/doctor_report_opener.dart';
import 'package:medibond/features/doctor/appointments/widgets/appointment_action_buttons.dart';
import 'package:medibond/features/doctor/appointments/widgets/appointment_chief_complaints_section.dart';
import 'package:medibond/features/doctor/appointments/widgets/appointment_symptoms_section.dart';
import 'package:medibond/features/doctor/clinical/clinical_tools_shell.dart';
import 'package:medibond/features/doctor/clinical/models/clinical_models.dart';
import 'package:medibond/features/doctor/clinical/prescription/prescription_pdf_service.dart';
import 'package:medibond/features/doctor/clinical/widgets/refer_specialist_dialog.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/doctor/patients/data/doctor_patients_service.dart';
import 'package:medibond/features/doctor/widgets/doctor_ui_widgets.dart';
import 'package:medibond/features/doctor/widgets/patient_sharing_blocked_notice.dart';
import 'package:medibond/features/patient/appointments/models/patient_appointment_models.dart';
import 'package:medibond/features/patient/appointments/patient_prescription_opener.dart';
import 'package:medibond/features/patient/appointments/widgets/appointment_card_shared.dart';
import 'package:medibond/features/patient/booking/booking_flow_screen.dart';
import 'package:medibond/features/patient/doctor_profile/models/doctor_profile_detail.dart';
import 'package:medibond/features/patient/doctor_profile/patient_doctor_profile_screen.dart';
import 'package:medibond/features/patient/profile/data/patient_profile_mock.dart';
import 'package:medibond/features/patient/profile/widgets/patient_profile_form_styles.dart';
import 'package:medibond/features/patient/utils/doctor_display_name.dart';
import 'package:medibond/features/patient/widgets/submit_doctor_review_sheet.dart';
import 'package:medibond/widgets/labeled_remove_button.dart';
import '../../../core/theme/app_typography.dart';


class AppointmentDetailScreen extends StatelessWidget {
  const AppointmentDetailScreen({
    super.key,
    this.isDoctorView = false,
    required this.appointment,
    this.onStatusChanged,
  });

  final bool isDoctorView;
  final dynamic appointment;
  final dynamic onStatusChanged;

  @override
  Widget build(BuildContext context) {
    if (isDoctorView) {
      return _DoctorAppointmentDetailScreen(
        appointment: appointment,
        onStatusChanged: onStatusChanged,
      );
    }
    return _PatientAppointmentDetailScreen(appointment: appointment);
  }
}

// --- DOCTOR VIEW IMPLEMENTATION ---



class _DoctorAppointmentDetailScreen extends StatefulWidget {
  const _DoctorAppointmentDetailScreen({
    super.key,
    required this.appointment,
    this.onStatusChanged,
  });

  final Appointment appointment;
  final ValueChanged<AppointmentStatus>? onStatusChanged;

  @override
  State<_DoctorAppointmentDetailScreen> createState() => _DoctorAppointmentDetailScreenState();
}

class _DoctorAppointmentDetailScreenState extends State<_DoctorAppointmentDetailScreen> {
  final _store = SharedAppointmentsStore.instance;
  bool _canViewClinicalData = true;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    unawaited(_loadSharingGate());
  }

  Future<void> _loadSharingGate() async {
    final record = _store.findRecordById(widget.appointment.id);
    final patientKey = record?.patientId?.trim();
    if (patientKey == null || patientKey.isEmpty) return;

    final canView = await DoctorPatientsService.canViewClinicalHistoryForKey(patientKey);
    if (!mounted) return;
    setState(() => _canViewClinicalData = canView);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
    unawaited(_loadSharingGate());
  }

  Appointment get appointment {
    return _store.doctorAppointmentForTarget(
          widget.appointment.id,
          DoctorSession.loggedInDoctorId,
        ) ??
        widget.appointment;
  }

  Future<void> _accept() async {
    try {
      await _store.acceptAppointment(appointment.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(e, fallback: "Couldn't accept this appointment. Please check your connection and try again."),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    widget.onStatusChanged?.call(AppointmentStatus.confirmed);
    setState(() {});
  }

  Future<void> _decline() async {
    try {
      await _store.declineAppointment(appointment.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(e, fallback: "Couldn't decline this appointment. Please check your connection and try again."),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    widget.onStatusChanged?.call(AppointmentStatus.cancelled);
    Navigator.pop(context);
  }

  static bool _canBookAmbulance(AppointmentStatus status) {
    return status != AppointmentStatus.cancelled &&
        status != AppointmentStatus.noShow;
  }

  Future<void> _openBookAmbulance(Appointment appt) async {
    final record = _store.findRecordById(appt.id);
    var name = appt.patientName.trim();
    var phone = appt.contactNumber?.trim() ?? record?.contactNumber?.trim() ?? '';

    final patientKey = record?.patientId;
    if (patientKey != null && patientKey.isNotEmpty) {
      if (phone.isEmpty || name.isEmpty) {
        for (final summary in DoctorPatientsService.summariesForDoctor(
          DoctorSession.loggedInDoctorId,
        )) {
          if (summary.id != patientKey) continue;
          if (phone.isEmpty && summary.mobile.trim().isNotEmpty) {
            phone = summary.mobile.trim();
          }
          if (name.isEmpty && summary.name.trim().isNotEmpty) {
            name = summary.name.trim();
          }
          break;
        }
      }

      if (phone.isEmpty || name.isEmpty) {
        try {
          final data = await FirestoreService.instance.patientProfile.fetchPatientDocumentForDoctor(
            patientKey,
          );
          if (data != null) {
            if (phone.isEmpty) {
              phone = (data['mobile'] as String?)?.trim() ?? '';
            }
            if (name.isEmpty) {
              name = (data['name'] as String?)?.trim() ?? name;
            }
          }
        } catch (_) {
          // Keep appointment values if profile lookup fails.
        }
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AmbulanceBookingScreen(
          bookedByRole: AmbulanceBookedByRole.doctor,
          initialPatientName: name,
          initialContactPhone: phone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appt = appointment;
    final record = _store.findRecordById(appt.id);
    final isPending = AppointmentStatusStyle.isPendingRequest(appt.status);

    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      appBar: AppBar(
        title: const Text('Appointment Details'),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        actions: [
          if (_canBookAmbulance(appt.status))
            _BookAmbulanceAppBarAction(
              onTap: () => _openBookAmbulance(appt),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveLayout.contentMaxWidth(context)),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (isPending) ...[
                      AppointmentActionButtons(
                        appointment: appt,
                        onAccept: _accept,
                        onDecline: _decline,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _PatientHeader(appointment: appt),
                    const SizedBox(height: 20),
                    if (appt.reasonForVisit != null) ...[
                      _InfoCard(
                        title: 'Reason for Visit',
                        child: Text(
                          appt.reasonForVisit!,
                          style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (appt.slotShareReason != null &&
                        appt.slotShareReason!.trim().isNotEmpty) ...[
                      _InfoCard(
                        title: appt.isSharedSlotEmergency
                            ? 'Shared Slot — Emergency'
                            : 'Shared Slot Reason',
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SharedSlotBadge(slotShareReason: appt.slotShareReason),
                            if (!appt.isSharedSlotEmergency) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  appt.slotShareReason!.trim(),
                                  style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, height: 1.4),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    AppointmentChiefComplaintsSection(
                      recordId: appt.id,
                      initialComplaints: record?.chiefComplaints ?? appt.chiefComplaints,
                    ),
                    const SizedBox(height: 16),
                    AppointmentSymptomsSection(
                      recordId: appt.id,
                      initialSymptoms: record?.symptoms ?? appt.symptoms,
                    ),
                    if (!_canViewClinicalData) ...[
                      const SizedBox(height: 16),
                      const PatientSharingBlockedNotice(compact: true),
                    ],
                    if (_canViewClinicalData &&
                        record?.diagnosis != null &&
                        record!.diagnosis!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _InfoCard(
                        title: 'Diagnosis',
                        child: Text(
                          record.diagnosis!,
                          style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, height: 1.4),
                        ),
                      ),
                    ],
                    if (_canViewClinicalData &&
                        record?.clinicalNotes != null &&
                        record!.clinicalNotes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _InfoCard(
                        title: 'Clinical Notes',
                        child: Text(
                          record.clinicalNotes!,
                          style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, height: 1.4),
                        ),
                      ),
                    ],
                    if (_canViewClinicalData && appt.reports.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _InfoCard(
                        title: 'Uploaded Reports',
                        child: Column(
                          children: appt.reports.map((r) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                r.fileType == 'pdf'
                                    ? Icons.picture_as_pdf_outlined
                                    : Icons.image_outlined,
                                color: AppColors.doctorBlue,
                              ),
                              title: Text(r.name, style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium)),
                              trailing: TextButton(
                                onPressed: () => DoctorReportOpener.open(
                                  context,
                                  reportName: r.name,
                                  patientId: record?.patientId,
                                ),
                                child: const Text('View'),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                    if (_canViewClinicalData && appt.pastVisits.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _InfoCard(
                        title: 'Past Visit History',
                        child: _VisitTimeline(visits: appt.pastVisits),
                      ),
                    ],
                    if (_canViewClinicalData && appt.lastVitals != null) ...[
                      const SizedBox(height: 16),
                      _InfoCard(
                        title: 'Vitals (Last Visit)',
                        child: _VitalsGrid(vitals: appt.lastVitals!),
                      ),
                    ],
                    if (!isPending) ...[
                      const SizedBox(height: 24),
                      _ActionGrid(
                        appointment: appt,
                        onStatusChanged: widget.onStatusChanged,
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

class _BookAmbulanceAppBarAction extends StatelessWidget {
  const _BookAmbulanceAppBarAction({required this.onTap});

  final VoidCallback onTap;

  static const _ambulanceRed = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(AmbulanceIcons.sign, size: 18, color: _ambulanceRed),
      label: Text(
        'Book Ambulance',
        style: GoogleFonts.inter(
          fontSize: AppTypography.bodySmall,
          fontWeight: FontWeight.w600,
          color: _ambulanceRed,
        ),
      ),
    );
  }
}

class _PatientHeader extends StatelessWidget {
  const _PatientHeader({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          PatientAvatar(
            name: appointment.patientName,
            gender: appointment.gender,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.patientName,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                  Text(
                    '${appointment.age} yrs · ${AppConstants.patientGenderLabel(appointment.gender)}',
                    style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat('dd MMM yyyy').format(appointment.appointmentDate)} · ${appointment.timeSlot}',
                    style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w500),
                  ),
                  if (appointment.slotShareReason != null &&
                      appointment.slotShareReason!.trim().isNotEmpty) ...[
                    SizedBox(height: 6),
                    SharedSlotBadge(slotShareReason: appointment.slotShareReason),
                  ],
                  if (appointment.contactNumber != null) ...[
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 14, color: AppColors.textSecondaryOf(context)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          appointment.contactNumber!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.doctorBlue),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '#${appointment.tokenNumber}',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineLarge,
                  fontWeight: FontWeight.w800,
                  color: AppColors.doctorBlue,
                ),
              ),
              StatusBadge(
                label: AppointmentStatusStyle.label(appointment.status),
                color: AppointmentStatusStyle.color(appointment.status),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _VisitTimeline extends StatelessWidget {
  const _VisitTimeline({required this.visits});

  final List<PastVisit> visits;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: visits.asMap().entries.map((entry) {
        final i = entry.key;
        final visit = entry.value;
        final isLast = i == visits.length - 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.doctorBlue,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Container(width: 2, height: 40, color: AppColors.borderOf(context)),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('dd MMM yyyy').format(visit.date),
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.doctorBlue,
                      ),
                    ),
                    Text(
                      visit.diagnosis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      visit.notes,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _VitalsGrid extends StatelessWidget {
  const _VitalsGrid({required this.vitals});

  final PatientVitals vitals;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('BP', vitals.bloodPressure, Icons.favorite_outline),
      ('Pulse', vitals.pulse, Icons.monitor_heart_outlined),
      ('Temp', vitals.temperature, Icons.thermostat_outlined),
      ('Weight', vitals.weight, Icons.monitor_weight_outlined),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              Icon(item.$3, size: 18, color: AppColors.doctorBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                    ),
                    Text(
                      item.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.appointment,
    this.onStatusChanged,
  });

  final Appointment appointment;
  final ValueChanged<AppointmentStatus>? onStatusChanged;

  PatientClinicalContext _patientContext() {
    final record = SharedAppointmentsStore.instance.findRecordById(appointment.id);
    double? weight;
    final w = appointment.lastVitals?.weight;
    if (w != null) {
      weight = double.tryParse(w.replaceAll(RegExp(r'[^\d.]'), ''));
    }
    String patientId = '';
    if (record != null) {
      final key = DoctorPatientsService.patientGroupKey(record);
      patientId = DoctorPatientsService.resolveRealPatientId(key);
    }
    if (patientId.isEmpty) {
      patientId = 'wi_${appointment.id}';
    }
    return PatientClinicalContext(
      patientName: appointment.patientName,
      age: appointment.age,
      gender: AppConstants.normalizePatientGender(appointment.gender),
      weightKg: weight,
      patientId: patientId,
      appointmentId: appointment.id,
    );
  }

  Future<void> _markComplete(BuildContext context) async {
    final record = SharedAppointmentsStore.instance.findRecordById(appointment.id);
    final controller = TextEditingController(
      text: record?.diagnosis ?? appointment.reasonForVisit ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete consultation'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Diagnosis (optional)',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
        ],
      ),
    );
    final diagnosis = controller.text;
    controller.dispose();
    if (confirmed != true || !context.mounted) return;

    SharedAppointmentsStore.instance.saveConsultationOutcome(
      recordId: appointment.id,
      diagnosis: diagnosis,
      markCompleted: true,
    );
    onStatusChanged?.call(AppointmentStatus.completed);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = appointment.status == AppointmentStatus.confirmed ||
        appointment.status == AppointmentStatus.inProgress ||
        appointment.status == AppointmentStatus.waiting;
    final ctx = _patientContext();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionTile(
          icon: Icons.edit_note_outlined,
          label: 'Write Prescription',
          onTap: () => ClinicalToolsShell.open(context, patient: ctx, initialTab: 0),
        ),
        _ActionTile(
          icon: Icons.note_add_outlined,
          label: 'Add Clinical Notes',
          onTap: () => ClinicalToolsShell.open(context, patient: ctx, initialTab: 1),
        ),
        _ActionTile(
          icon: Icons.person_add_alt_1_outlined,
          label: 'Refer Patient',
          onTap: () => ReferSpecialistDialog.show(context, patient: ctx),
        ),
        if (isActive)
          _ActionTile(
            icon: Icons.check_circle_outline,
            label: 'Mark Complete',
            color: const Color(0xFF16A34A),
            onTap: () => _markComplete(context),
          ),
        if (isActive)
          _ActionTile(
            icon: AppIcons.reschedule,
            label: 'Reschedule',
            onTap: () => DoctorAppointmentActions.reschedule(
              context,
              appointment: appointment,
            ),
          ),
        if (isActive)
          _ActionTile(
            icon: Icons.cancel_outlined,
            label: 'Cancel Appointment',
            color: const Color(0xFFDC2626),
            onTap: () => DoctorAppointmentActions.cancel(
              context,
              appointment: appointment,
              onComplete: () => onStatusChanged?.call(AppointmentStatus.cancelled),
              popAfter: true,
            ),
          ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.doctorBlue;
    return SizedBox(
      width: (ResponsiveLayout.contentMaxWidth(context) - 56) / 2,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: c),
        label: Text(
          label,
          style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: c),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}


// --- PATIENT VIEW IMPLEMENTATION ---


class _PatientAppointmentDetailScreen extends StatelessWidget {
  const _PatientAppointmentDetailScreen({super.key, required this.appointment});

  final PatientAppointment appointment;

  PatientAppointment _resolveAppointment() {
    for (final a in SharedAppointmentsStore.instance.patientAppointments()) {
      if (a.id == appointment.id) return a;
    }
    return appointment;
  }

  bool _isCancelled(PatientAppointment a) => a.cancellationReason != null;

  bool _isUpcoming(PatientAppointment a) =>
      !_isCancelled(a) && a.dateTime.isAfter(DateTime.now().subtract(const Duration(hours: 1)));

  void _reschedule(BuildContext context, PatientAppointment a) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reschedule', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        content: Text('Pick a new slot for your visit with ${formatDoctorDisplayName(a.doctorName)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BookingFlowScreen(
                    doctorId: a.doctorId,
                    rescheduleFromRecordId: a.id,
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.patientTeal),
            child: const Text('Pick new slot'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, PatientAppointment a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel appointment?', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        content: const Text('Cancellation may be subject to clinic policy.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cancel appointment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await SharedAppointmentsStore.instance.cancelByPatient(
        a.id,
        reason: 'Cancelled by patient',
      );
      DoctorNotificationEmitter.notifyAppointmentCancelledByPatient(
        patientName: PatientProfileMock.profile.name,
        dateTimeLabel: DateFormat('dd MMM, hh:mm a').format(a.dateTime),
        reason: 'Cancelled by patient',
        appointmentId: a.appointmentId,
      );
      if (!context.mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(e, fallback: "Couldn't cancel this appointment. Please check your connection and try again."),
          ),
        ),
      );
    }
  }

  Future<void> _rateDoctor(BuildContext context, PatientAppointment a) async {
    final patientId = PatientSession.loggedInPatientId;
    PatientDoctorReview? existingReview;
    if (patientId.isNotEmpty) {
      existingReview = await FirestoreService.instance.review.fetchReviewForPatientAndDoctor(
        patientId: patientId,
        doctorId: a.doctorId,
      );
    }
    if (!context.mounted) return;

    final isEdit = existingReview != null || a.hasReview;
    final submitted = await SubmitDoctorReviewSheet.show(
      context,
      doctorName: a.doctorName,
      isEdit: isEdit,
      initialRating: existingReview?.rating ?? a.reviewRating,
      initialComment: existingReview?.text,
      onSubmit: (rating, comment) => SharedAppointmentsStore.instance.submitReview(
        recordId: a.id,
        rating: rating,
        comment: comment,
      ),
    );
    if (!context.mounted || submitted != true) return;
  }

  Future<void> _editReview(BuildContext context, PatientAppointment a) async {
    String? initialComment;
    if (a.reviewId != null && a.reviewId!.isNotEmpty) {
      final review = await FirestoreService.instance.review.fetchReview(a.reviewId!);
      initialComment = review?.text;
    }
    if (!context.mounted) return;

    final updated = await SubmitDoctorReviewSheet.show(
      context,
      doctorName: a.doctorName,
      isEdit: true,
      initialRating: a.reviewRating,
      initialComment: initialComment,
      onSubmit: (rating, comment) => SharedAppointmentsStore.instance.updateReview(
        recordId: a.id,
        rating: rating,
        comment: comment,
      ),
    );
    if (!context.mounted || updated != true) return;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SharedAppointmentsStore.instance,
      builder: (context, _) {
        final a = _resolveAppointment();
        return _buildScaffold(context, a);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, PatientAppointment a) {
    final cancelled = _isCancelled(a);
    final upcoming = _isUpcoming(a);

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('Appointment Details', context: context),
      body: PatientProfileFormStyles.constrainedScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusHeader(
              appointment: a,
              cancelled: cancelled,
              upcoming: upcoming,
            ),
            const SizedBox(height: 16),
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    DateFormat('EEEE, dd MMMM yyyy').format(a.dateTime),
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyLarge,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('hh:mm a').format(a.dateTime),
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineLarge,
                      fontWeight: FontWeight.w800,
                      color: AppColors.patientTeal,
                      height: 1.1,
                    ),
                  ),
                  if (upcoming) ...[
                    const SizedBox(height: 8),
                    Text(
                      a.countdownLabel,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.patientTeal,
                      ),
                    ),
                  ],
                  SizedBox(height: 16),
                  Divider(height: 1, color: AppColors.borderOf(context)),
                  const SizedBox(height: 16),
                  _DetailRow(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Token',
                    value: '#${a.tokenNumber}',
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(
                    icon: Icons.local_hospital_outlined,
                    label: 'Visit type',
                    value: 'In-clinic visit',
                  ),
                  if (a.clinicName != null && a.clinicName!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _DetailRow(
                      icon: Icons.apartment_outlined,
                      label: 'Clinic',
                      value: a.clinicName!,
                    ),
                  ],
                  if (a.clinicAddress != null && a.clinicAddress!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: 'Location',
                      value: a.clinicAddress!,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            PatientProfileFormStyles.contentSurface(context: context, child: Row(
                children: [
                  appointmentDoctorAvatar(a.doctorName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatDoctorDisplayName(a.doctorName),
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.headlineSmall,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.specialization,
                          style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
                        ),
                        if (appointmentDoctorRatingBadge(a.doctorId) != null) ...[
                          const SizedBox(height: 6),
                          appointmentDoctorRatingBadge(a.doctorId)!,
                        ],
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientDoctorProfileScreen(doctorId: a.doctorId),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.patientTeal,
                      side: const BorderSide(color: AppColors.patientTeal),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View profile'),
                  ),
                ],
              ),
            ),
            if (a.reasonForVisit != null && a.reasonForVisit!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionCard(title: 'Reason for visit', body: a.reasonForVisit!),
            ],
            if (a.diagnosis != null && a.diagnosis!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionCard(title: 'Diagnosis', body: a.diagnosis!),
            ],
            if (a.hasPrescription) ...[
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Prescription',
                body: 'Issued by ${formatDoctorDisplayName(a.doctorName)}',
                actions: [
                  TextButton(
                    onPressed: () => PatientPrescriptionOpener.open(context, a),
                    child: const Text('View'),
                  ),
                  TextButton(
                    onPressed: () => _downloadPrescription(context, a),
                    child: const Text('Download'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () => _sharePrescription(context, a),
                  ),
                ],
              ),
            ],
            if (a.labReports.isNotEmpty) ...[
              const SizedBox(height: 16),
              PatientProfileFormStyles.contentSurface(context: context, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lab reports',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.bodyMedium),
                    ),
                    const SizedBox(height: 8),
                    ...a.labReports.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.biotech_outlined, size: 18, color: AppColors.patientTeal),
                            const SizedBox(width: 8),
                            Expanded(child: Text(r, style: GoogleFonts.inter(fontSize: AppTypography.bodySmall))),
                            TextButton(
                              onPressed: () {},
                              child: const Text('View'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (a.clinicalNotes != null && a.clinicalNotes!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionCard(title: 'Clinical notes (shared)', body: a.clinicalNotes!),
            ],
            const SizedBox(height: 16),
            if (upcoming)
              _ActionsCard(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _reschedule(context, a),
                      icon: const Icon(AppIcons.reschedule, size: 18),
                      label: const Text('Reschedule'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.patientTeal,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: LabeledRemoveButton(
                      label: 'Cancel appointment',
                      compact: false,
                      onPressed: () => _cancel(context, a),
                    ),
                  ),
                ],
              )
            else if (!cancelled) ...[
              if (!a.hasReview)
                _ActionsCard(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _rateDoctor(context, a),
                        icon: const Icon(Icons.star_outline, size: 20),
                        label: const Text('Rate doctor'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.patientTeal,
                          minimumSize: const Size(0, 48),
                          side: const BorderSide(color: AppColors.patientTeal),
                        ),
                      ),
                    ),
                  ],
                )
              else if (a.canEditReview)
                _ActionsCard(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _editReview(context, a),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        label: const Text('Edit review (48 hrs)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.patientTeal,
                          minimumSize: const Size(0, 48),
                          side: const BorderSide(color: AppColors.patientTeal),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => BookingFlowScreen(doctorId: a.doctorId)),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.patientTeal,
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Book again'),
                ),
              ),
            ] else
              _ActionsCard(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => BookingFlowScreen(doctorId: a.doctorId)),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.patientTeal,
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('Book again'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    AppToast.info(context, msg);
  }

  Future<void> _downloadPrescription(BuildContext context, PatientAppointment a) async {
    try {
      final draft = await PatientPrescriptionOpener.loadDraft(a);
      if (!context.mounted) return;
      if (draft == null) {
        _snack(context, 'Prescription not found.');
        return;
      }
      await PrescriptionPdfService.sharePdf(draft);
    } catch (_) {
      if (!context.mounted) return;
      _snack(context, 'Could not download prescription.');
    }
  }

  Future<void> _sharePrescription(BuildContext context, PatientAppointment a) async {
    try {
      final draft = await PatientPrescriptionOpener.loadDraft(a);
      if (!context.mounted) return;
      if (draft == null) {
        _snack(context, 'Prescription not found.');
        return;
      }
      await PrescriptionPdfService.sharePdf(draft);
    } catch (_) {
      if (!context.mounted) return;
      _snack(context, 'Could not share prescription.');
    }
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.appointment,
    required this.cancelled,
    required this.upcoming,
  });

  final PatientAppointment appointment;
  final bool cancelled;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch ((cancelled, upcoming)) {
      (true, _) => ('Cancelled', const Color(0xFFDC2626), const Color(0xFFFEF2F2)),
      (false, true) => (
          appointment.status == PatientBookingStatus.confirmed ? 'Confirmed' : 'Pending',
          appointment.status == PatientBookingStatus.confirmed
              ? const Color(0xFF16A34A)
              : const Color(0xFFD97706),
          appointment.status == PatientBookingStatus.confirmed
              ? const Color(0xFFF0FDF4)
              : const Color(0xFFFFFBEB),
        ),
      _ => ('Completed', const Color(0xFF2563EB), const Color(0xFFEFF6FF)),
    };

    return PatientProfileFormStyles.contentSurface(context: context, child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                if (appointment.appointmentId != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'ID: ${appointment.appointmentId}',
                    style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
                  ),
                ],
                if (cancelled && appointment.cancellationReason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    appointment.cancellationReason!,
                    style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.patientTeal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              cancelled
                  ? Icons.event_busy_outlined
                  : upcoming
                      ? Icons.event_available_outlined
                      : Icons.event_available,
              color: AppColors.patientTeal,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.patientTeal),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return PatientProfileFormStyles.contentSurface(context: context, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.bodyMedium)),
          const SizedBox(height: 8),
          Text(body, style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, height: 1.4)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: actions),
          ],
        ],
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PatientProfileFormStyles.contentSurface(context: context, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
