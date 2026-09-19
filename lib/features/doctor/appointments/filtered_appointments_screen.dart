import '../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/data/shared_appointments_store.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/doctor_session.dart';
import '../../../core/firebase/firebase_error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../clinical/clinical_tools_shell.dart';
import '../clinical/models/clinical_models.dart';
import '../models/doctor_models.dart';
import 'package:medibond/features/shared/screens/appointment_detail_screen.dart';
import 'appointment_utils.dart';
import 'widgets/appointment_tab_card.dart';
import 'widgets/appointments_empty_state.dart';
import 'appointment_actions.dart';

class FilteredAppointmentsScreen extends StatefulWidget {
  final String title;
  final AppointmentListTab tab;
  final DateTime? selectedDate;

  const FilteredAppointmentsScreen({
    super.key,
    required this.title,
    required this.tab,
    this.selectedDate,
  });

  @override
  State<FilteredAppointmentsScreen> createState() => _FilteredAppointmentsScreenState();
}

class _FilteredAppointmentsScreenState extends State<FilteredAppointmentsScreen> {
  static const _contentMaxWidth = 960.0;

  final _store = SharedAppointmentsStore.instance;

  List<Appointment> get _appointments =>
      _store.doctorAppointments(DoctorSession.loggedInDoctorId);

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  List<Appointment> get _filteredAppointments {
    final selected = widget.selectedDate;
    if (selected != null) {
      final list = _store.appointmentsForDoctorOnDate(
        DoctorSession.loggedInDoctorId,
        selected,
      )
        ..sort((a, b) => a.timeSlot.compareTo(b.timeSlot));
      return list;
    }

    return AppointmentFilters.apply(
      source: _appointments,
      tab: widget.tab,
    );
  }

  void _updateStatus(String id, AppointmentStatus status) {
    _store.updateDoctorStatus(id, status);
  }

  void _openDetail(Appointment appointment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentDetailScreen(isDoctorView: true, 
          appointment: appointment,
          onStatusChanged: (s) => _updateStatus(appointment.id, s),
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _cancelAppointment(Appointment appointment) {
    DoctorAppointmentActions.cancel(
      context,
      appointment: appointment,
      onComplete: () => setState(() {}),
    );
  }

  Future<void> _acceptAppointment(Appointment appointment) async {
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
    setState(() {});
  }

  Future<void> _declineAppointment(Appointment appointment) async {
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
    setState(() {});
  }

  void _startConsultation(Appointment appointment) {
    final record = _store.findRecordById(appointment.id);
    final resolvedPatientId = record?.patientId;
    if (resolvedPatientId == null || resolvedPatientId.isEmpty) {
      AppToast.info(context, 'This patient is not registered yet — clinical tools cannot be linked to them.');
      return;
    }
    _updateStatus(appointment.id, AppointmentStatus.inProgress);
    double? weight;
    final w = appointment.lastVitals?.weight;
    if (w != null) {
      weight = double.tryParse(w.replaceAll(RegExp(r'[^\d.]'), ''));
    }
    ClinicalToolsShell.open(
      context,
      patient: PatientClinicalContext(
        patientName: appointment.patientName,
        age: appointment.age,
        gender: AppConstants.normalizePatientGender(appointment.gender),
        weightKg: weight,
        patientId: resolvedPatientId,
        appointmentId: appointment.id,
      ),
      initialTab: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredAppointments;
    final wide = !ResponsiveLayout.isCompact(context);
    final horizontalPadding = wide ? 24.0 : 16.0;
    
    String emptyTabLabel = 'Today';
    if (widget.selectedDate != null) {
      emptyTabLabel = DateFormat('EEE, d MMM yyyy').format(widget.selectedDate!);
    } else {
      switch (widget.tab) {
        case AppointmentListTab.today:
          emptyTabLabel = 'Today';
          break;
        case AppointmentListTab.upcoming:
          emptyTabLabel = 'Upcoming';
          break;
        case AppointmentListTab.pending:
          emptyTabLabel = 'Pending';
          break;
        case AppointmentListTab.completed:
          emptyTabLabel = 'Completed';
          break;
        case AppointmentListTab.cancelled:
          emptyTabLabel = 'Cancelled';
          break;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          widget.title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: wide ? _contentMaxWidth : double.infinity,
          ),
          child: list.isEmpty
              ? AppointmentsEmptyState(tabLabel: emptyTabLabel)
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 20),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final appt = list[index];
                    return AppointmentTabCard(
                      appointment: appt,
                      onTap: () => _openDetail(appt),
                      onAccept: () => _acceptAppointment(appt),
                      onDecline: () => _declineAppointment(appt),
                      onStart: () => _startConsultation(appt),
                      onView: () => _openDetail(appt),
                      onCancel: () => _cancelAppointment(appt),
                      onReschedule: () => DoctorAppointmentActions.reschedule(
                        context,
                        appointment: appt,
                        onComplete: () => setState(() {}),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
