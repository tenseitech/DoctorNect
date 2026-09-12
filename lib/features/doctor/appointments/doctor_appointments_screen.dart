import '../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/data/shared_appointments_store.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/doctor_session.dart';
import '../../../core/firebase/firebase_error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../clinical/clinical_tools_shell.dart';
import '../clinical/models/clinical_models.dart';
import '../models/doctor_models.dart';
import '../widgets/doctor_screen_title_bar.dart';
import 'package:medibond/features/shared/screens/appointment_detail_screen.dart';
import 'appointment_utils.dart';
import 'widgets/appointment_filters_bar.dart';
import 'widgets/appointment_tab_card.dart';
import 'widgets/appointments_empty_state.dart';
import 'appointment_actions.dart';

class DoctorAppointmentsScreen extends StatefulWidget {
  const DoctorAppointmentsScreen({super.key, this.initialTabIndex = 0});

  /// 0 Today, 1 Upcoming, 2 Completed, 3 Cancelled
  final int initialTabIndex;

  @override
  State<DoctorAppointmentsScreen> createState() =>
      _DoctorAppointmentsScreenState();
}

class _DoctorAppointmentsScreenState extends State<DoctorAppointmentsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final _store = SharedAppointmentsStore.instance;

  DateTime? _filterDate;
  AppointmentType? _typeFilter;
  final _searchController = TextEditingController();
  static const _tabLabels = ['Today', 'Upcoming', 'Pending', 'Completed', 'Cancelled'];
  static const _tabs = [
    AppointmentListTab.today,
    AppointmentListTab.upcoming,
    AppointmentListTab.pending,
    AppointmentListTab.completed,
    AppointmentListTab.cancelled,
  ];

  List<Appointment> get _appointments =>
      _store.doctorAppointments(DoctorSession.loggedInDoctorId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final tab = widget.initialTabIndex.clamp(0, 4);
    _tabController = TabController(length: 5, vsync: this, initialIndex: tab);
    _tabController.addListener(_onTabChanged);
    _searchController.addListener(() => setState(() {}));
    unawaited(_refreshAppointments());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAppointments());
    }
  }

  Future<void> _refreshAppointments() async {
    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isEmpty) return;
    await _store.refreshForDoctor(
      doctorId,
      force: true,
      preferCache: false,
    );
  }

  void _onTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    if (_tabController.index == 0 && _filterDate != null) {
      setState(() => _filterDate = null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Appointment> _filteredForTab(AppointmentListTab tab) {
    return AppointmentFilters.apply(
      source: _appointments,
      tab: tab,
      filterDate: tab == AppointmentListTab.today ? null : _filterDate,
      typeFilter: _typeFilter,
      searchQuery: _searchController.text,
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
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Accepted — ${appointment.patientName}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Declined — ${appointment.patientName}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  static const _contentMaxWidth = 960.0;

  @override
  Widget build(BuildContext context) {
    final wide = !ResponsiveLayout.isCompact(context);
    final horizontalPadding = wide ? 24.0 : 16.0;

    return ColoredBox(
      color: wide ? AppColors.cardBgOf(context) : AppColors.surfaceOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DoctorScreenTitleBar(title: 'Appointments'),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wide ? _contentMaxWidth : double.infinity,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: AppColors.surfaceOf(context),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        labelColor: AppColors.doctorBlue,
                        unselectedLabelColor: AppColors.textSecondaryOf(context),
                        indicatorColor: AppColors.doctorBlue,
                        labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: GoogleFonts.inter(fontSize: 14),
                        tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
                        onTap: (_) => setState(() {}),
                      ),
                    ),
                    AppointmentFiltersBar(
                      showDateFilter: _tabController.index != 0,
                      filterDate: _filterDate,
                      typeFilter: _typeFilter,
                      searchController: _searchController,
                      onDateChanged: (d) => setState(() => _filterDate = d),
                      onTypeChanged: (t) => setState(() => _typeFilter = t),
                      onSearchChanged: () => setState(() {}),
                    ),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: _store,
                        builder: (context, _) {
                          return TabBarView(
                            physics: const NeverScrollableScrollPhysics(),
                            controller: _tabController,
                            children: _tabs.map((tab) {
                              final list = _filteredForTab(tab);
                              if (list.isEmpty) {
                                return AppointmentsEmptyState(tabLabel: _tabLabels[_tabs.indexOf(tab)]);
                              }
                              return ListView.builder(
                                padding: EdgeInsets.fromLTRB(
                                  horizontalPadding,
                                  12,
                                  horizontalPadding,
                                  20,
                                ),
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
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
