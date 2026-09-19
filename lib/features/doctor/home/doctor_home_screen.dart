import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/data/shared_appointments_store.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/doctor_session.dart';
import '../../ambulance/ambulance_booking_screen.dart';
import '../../ambulance/models/ambulance_models.dart';
import '../../../core/firebase/firebase_error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../patients/data/doctor_patients_service.dart';
import '../profile/data/doctor_profile_store.dart';
import '../data/doctor_home_carousel_data.dart';
import '../models/doctor_models.dart';
import '../schedule/availability_screen.dart';
import '../appointments/appointment_actions.dart';
import '../appointments/appointment_utils.dart';
import 'package:medibond/features/shared/screens/appointment_detail_screen.dart';
import '../appointments/filtered_appointments_screen.dart';
import '../clinical/clinical_tools_shell.dart';
import '../clinical/lab/lab_test_order_screen.dart';
import '../clinical/models/clinical_models.dart';
import '../profile/sections/reviews_section.dart';
import '../../patient/data/registered_doctors_store.dart';
import '../../promoted_ads/screens/promoted_ads_management_screen.dart';
import '../../patient/doctor_profile/patient_doctor_profile_screen.dart';
import '../network/invite_network_view.dart';
import '../network/refer_doctor_view.dart';
import '../patients/widgets/walkin_patient_sheet.dart';
import '../../../widgets/home_banner_carousel.dart';
import 'widgets/doctor_home_sections.dart';
import 'widgets/doctor_appointment_calendar.dart';
import 'widgets/doctor_date_patient_list.dart';
import 'widgets/doctor_referred_patients_screen.dart';
import 'widgets/patient_picker_sheet.dart';
import 'widgets/doctor_global_search_sheet.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({
    super.key,
    this.onOpenAppointments,
  });

  /// [tabIndex]: 0 Today, 1 Upcoming, 2 Completed, 3 Cancelled
  final void Function(int tabIndex)? onOpenAppointments;

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen>
    with WidgetsBindingObserver {
  final _store = SharedAppointmentsStore.instance;
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  int _referredCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isNotEmpty) {
      unawaited(_refreshAppointments());
      // Featured carousel needs doctor directory.
      unawaited(RegisteredDoctorsStore.instance.refreshFromFirestore());
      unawaited(_loadReferredCount());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

  Future<void> _loadReferredCount() async {
    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isEmpty) return;
    final results = await Future.wait([
      FirestoreService.instance.referral.fetchSentByDoctor(doctorId),
      FirestoreService.instance.referral.fetchReceivedByDoctor(doctorId),
    ]);
    if (!mounted) return;
    setState(() => _referredCount = results[0].length + results[1].length);
  }

  Future<void> _openReferredPatients() async {
    await DoctorReferredPatientsScreen.open(context);
    if (!mounted) return;
    unawaited(_loadReferredCount());
  }

  void _onCarouselCta(String? route) {
    switch (route) {
      case 'availability':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AvailabilityScreen()),
        );
      case 'prescription':
        unawaited(_openPrescriptionWithSearch());
      case 'reviews':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReviewsSection()),
        );
      case 'invite':
        InviteNetworkView.show(context);
      default:
        if (route != null && route.startsWith('featured_doctor:')) {
          final doctorId = route.substring('featured_doctor:'.length);
          if (doctorId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PatientDoctorProfileScreen(doctorId: doctorId),
              ),
            );
          }
        }
        break;
    }
  }

  Future<void> _openPrescriptionWithSearch() async {
    await DoctorPatientsService.refreshOnTabOpen();
    if (!mounted) return;
    final summaries = DoctorPatientsService.summariesForDoctor(
        DoctorSession.loggedInDoctorId);
    final mapped = summaries
        .map((s) => Appointment(
              id: s.id,
              tokenNumber: 0,
              patientName: s.name,
              age: s.age,
              gender: s.gender,
              appointmentDate: s.lastVisitDate,
              timeSlot: '',
              status: AppointmentStatus.confirmed,
              type: AppointmentType.newVisit,
            ))
        .toList();

    final picked = await PatientPickerSheet.show(
      context,
      title: 'Write Prescription',
      subtitle: 'Search and pick a patient',
      appointments: mapped,
    );
    if (picked == null || !mounted) return;

    final resolvedPatientId =
        DoctorPatientsService.resolveRealPatientId(picked.id);
    if (resolvedPatientId.isEmpty) {
      AppToast.info(context,
          'This patient is not registered yet — the prescription cannot be linked to them.');
      return;
    }
    await ClinicalToolsShell.open(
      context,
      patient: PatientClinicalContext(
        patientName: picked.patientName,
        age: picked.age,
        gender: AppConstants.normalizePatientGender(picked.gender),
        patientId: resolvedPatientId,
        appointmentId: '', // No specific appointment context
      ),
      initialTab: 0,
    );
  }

  Future<void> _openLabOrderWithSearch() async {
    await DoctorPatientsService.refreshOnTabOpen();
    if (!mounted) return;
    final summaries = DoctorPatientsService.summariesForDoctor(
        DoctorSession.loggedInDoctorId);
    final mapped = summaries
        .map((s) => Appointment(
              id: s.id,
              tokenNumber: 0,
              patientName: s.name,
              age: s.age,
              gender: s.gender,
              appointmentDate: s.lastVisitDate,
              timeSlot: '',
              status: AppointmentStatus.confirmed,
              type: AppointmentType.newVisit,
            ))
        .toList();

    final picked = await PatientPickerSheet.show(
      context,
      title: 'Order Lab Test',
      subtitle: 'Search and pick a patient',
      appointments: mapped,
    );
    if (picked == null || !mounted) return;

    final resolvedPatientId =
        DoctorPatientsService.resolveRealPatientId(picked.id);
    if (resolvedPatientId.isEmpty) {
      AppToast.info(context,
          'This patient is not registered yet — the lab order cannot be linked to them.');
      return;
    }

    final patient = PatientClinicalContext(
      patientName: picked.patientName,
      age: picked.age,
      gender: AppConstants.normalizePatientGender(picked.gender),
      patientId: resolvedPatientId,
      appointmentId: '',
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          backgroundColor: AppColors.cardBgOf(context),
          appBar: AppBar(
            title: Text('Order Lab Test — ${patient.patientName}'),
            backgroundColor: AppColors.surfaceOf(context),
            foregroundColor: AppColors.textPrimaryOf(context),
            elevation: 0,
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveLayout.contentMaxWidth(routeContext),
              ),
              child: LabTestOrderScreen(
                patient: patient,
                source: 'dashboard',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openGlobalSearch() async {
    await DoctorGlobalSearchScreen.show(
      context,
      onPatientSelected: (picked) async {
        final resolvedPatientId =
            DoctorPatientsService.resolveRealPatientId(picked.id);
        if (resolvedPatientId.isEmpty) {
          AppToast.info(context,
              'This patient is not registered yet — cannot open records.');
          return;
        }
        await ClinicalToolsShell.open(
          context,
          patient: PatientClinicalContext(
            patientName: picked.patientName,
            age: picked.age,
            gender: AppConstants.normalizePatientGender(picked.gender),
            patientId: resolvedPatientId,
            appointmentId: '',
          ),
          initialTab: 0,
        );
      },
    );
  }

  Future<void> _openRescheduleWithSearch() async {
    final reschedulable = _store
        .doctorAppointments(DoctorSession.loggedInDoctorId)
        .where((a) => AppointmentStatusStyle.isUpcomingActionable(a.status))
        .toList();

    if (reschedulable.isEmpty) {
      if (!mounted) return;
      AppToast.info(context, 'No appointments available to reschedule');
      return;
    }

    final picked = await PatientPickerSheet.show(
      context,
      title: 'Reschedule Appointment',
      subtitle: 'Search and pick an appointment',
      appointments: reschedulable,
      showAppointmentDate: true,
    );
    if (picked == null || !mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    DoctorAppointmentActions.reschedule(
      context,
      appointment: picked,
      onComplete: () {
        if (mounted) setState(() {});
      },
    );
  }

  void _openReviews() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReviewsSection()),
    );
  }

  List<DoctorHomeStatItem> _buildStatItems() {
    final stats = _statsForDoctor();
    return [
      DoctorHomeStatItem(
        label: 'Today',
        value: '${stats.todaysAppointments}',
        gradient: const [AppColors.doctorBlue, Color(0xFF0F4A82)],
        icon: TablerIcons.calendar_event,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FilteredAppointmentsScreen(
                title: 'Today\'s Appointments',
                tab: AppointmentListTab.today,
              ),
            ),
          );
        },
      ),
      DoctorHomeStatItem(
        label: 'Pending',
        value: '${stats.pending}',
        gradient: const [Color(0xFFEA580C), Color(0xFFC2410C)],
        icon: TablerIcons.clock,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FilteredAppointmentsScreen(
                title: 'Pending Appointments',
                tab: AppointmentListTab.pending,
              ),
            ),
          );
        },
      ),
      DoctorHomeStatItem(
        label: 'Completed',
        value: '${stats.completed}',
        gradient: const [Color(0xFF16A34A), Color(0xFF15803D)],
        icon: TablerIcons.circle_check,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FilteredAppointmentsScreen(
                title: 'Completed Appointments',
                tab: AppointmentListTab.completed,
              ),
            ),
          );
        },
      ),
      DoctorHomeStatItem(
        label: 'Refer',
        value: '$_referredCount',
        gradient: const [Color(0xFF7C3AED), Color(0xFF6D28D9)],
        icon: TablerIcons.share_3,
        onTap: _openReferredPatients,
      ),
    ];
  }

  List<DoctorHomeServiceItem> _networkServices() {
    final isVerified =
        DoctorProfileStore.instance.dashboardVerificationStatus ==
            VerificationStatus.verified;

    return [
      DoctorHomeServiceItem(
        label: 'Invite and Connect',
        shortLabel: 'Invite',
        subtitle: 'Grow your network',
        icon: TablerIcons.users_plus,
        gradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
        onTap: () => InviteNetworkView.show(context),
      ),
      DoctorHomeServiceItem(
        label: 'Promote Practice',
        shortLabel: 'Promote',
        subtitle: 'Banner ads on Patient Home',
        icon: TablerIcons.speakerphone,
        gradient: const [Color(0xFF7C3AED), Color(0xFF6D28D9)],
        onTap: () {
          PromotedAdsManagementScreen.open(
            context,
            providerType: 'doctor',
            providerId: DoctorSession.loggedInDoctorId,
            providerEmail: DoctorProfileStore.instance.profile.email,
            providerContact: DoctorProfileStore.instance.profile.mobile,
            isVerified: isVerified,
          );
        },
      ),
      DoctorHomeServiceItem(
        label: 'Add New Patient',
        shortLabel: 'Add Patient',
        subtitle: 'Walk-in registration',
        icon: TablerIcons.user_plus,
        gradient: const [Color(0xFF0D9488), Color(0xFF0369A1)],
        onTap: _openAddNewPatient,
      ),
      DoctorHomeServiceItem(
        label: 'My Reviews',
        shortLabel: 'Reviews',
        subtitle: 'Patient feedback',
        icon: TablerIcons.star,
        gradient: const [Color(0xFFCA8A04), Color(0xFFA16207)],
        onTap: _openReviews,
      ),
      DoctorHomeServiceItem(
        label: 'Refer another Doctor',
        shortLabel: 'Refer',
        subtitle: 'Send a referral',
        icon: TablerIcons.share_3,
        gradient: const [Color(0xFF0F766E), Color(0xFF0D9488)],
        onTap: () => ReferDoctorView.show(context),
      ),
    ];
  }

  List<DoctorHomeServiceItem> _clinicalServices() {
    return [
      DoctorHomeServiceItem(
        label: 'Set Availability',
        shortLabel: 'Availability',
        subtitle: 'Manage slots',
        icon: TablerIcons.calendar_time,
        gradient: const [Color(0xFFEA580C), Color(0xFFC2410C)],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AvailabilityScreen()),
        ),
      ),
      DoctorHomeServiceItem(
        label: 'Add Prescription',
        shortLabel: 'Prescription',
        subtitle: 'Write for patient',
        icon: AppIcons.prescription,
        gradient: const [Color(0xFF16A34A), Color(0xFF15803D)],
        onTap: _openPrescriptionWithSearch,
      ),
      DoctorHomeServiceItem(
        label: 'Order Lab Test',
        shortLabel: 'Lab Test',
        subtitle: 'Send tests for a patient',
        icon: TablerIcons.flask,
        gradient: const [Color(0xFF7C3AED), Color(0xFF6D28D9)],
        onTap: _openLabOrderWithSearch,
      ),
      DoctorHomeServiceItem(
        label: 'Today\'s Queue',
        shortLabel: 'Queue',
        subtitle: 'Today\'s patients',
        icon: TablerIcons.list_check,
        gradient: const [AppColors.doctorBlue, Color(0xFF0F4A82)],
        onTap: () => widget.onOpenAppointments?.call(0),
      ),
      DoctorHomeServiceItem(
        label: 'Reschedule Appointment',
        shortLabel: 'Reschedule',
        subtitle: 'Move a visit',
        icon: AppIcons.reschedule,
        gradient: const [Color(0xFF0891B2), Color(0xFF0E7490)],
        onTap: _openRescheduleWithSearch,
      ),
      DoctorHomeServiceItem(
        label: 'Ambulance',
        shortLabel: 'Ambulance',
        subtitle: 'Emergency help',
        icon: TablerIcons.ambulance,
        gradient: const [Color(0xFFDC2626), Color(0xFFB91C1C)],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AmbulanceBookingScreen(
              bookedByRole: AmbulanceBookedByRole.doctor,
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.cardBgOf(context),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                DoctorProfileStore.instance,
                _store,
              ]),
              builder: (context, _) {
                final profileData = DoctorProfileStore.instance.profile;
                final profile = DoctorProfile(
                  name: profileData.fullName,
                  verificationStatus:
                      DoctorProfileStore.instance.dashboardVerificationStatus,
                );
                final name = profile.name.trim().isNotEmpty
                    ? profile.name.trim()
                    : DoctorSession.loggedInDoctorName.trim();

                final compact = ResponsiveLayout.isCompact(context);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DoctorHomeTopBar(
                      displayName: name,
                      verificationStatus: profile.verificationStatus,
                    ),
                    DoctorHomeStatsStrip(
                      items: _buildStatItems(),
                      selectedDate: _selectedDate,
                      onCalendarTap: _openCalendarPopup,
                      onSearchTap: compact ? _openGlobalSearch : null,
                    ),
                    if (!compact)
                      DoctorHomePatientSearchBar(
                        onTap: _openGlobalSearch,
                      ),
                  ],
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                _store,
                RegisteredDoctorsStore.instance,
              ]),
              builder: (context, _) {
                final carouselItems = DoctorHomeCarouselData.buildItems();
                if (carouselItems.isEmpty) return const SizedBox.shrink();
                final isWide = MediaQuery.sizeOf(context).width >= 600;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                      isWide ? 0 : 16, isWide ? 16 : 4, isWide ? 0 : 16, 0),
                  child: HomeBannerCarousel(
                    items: carouselItems,
                    dotActiveColor: AppColors.doctorBlue,
                    onCtaTap: _onCarouselCta,
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DoctorHomeServicesSection(
                  title: 'Grow your practice',
                  services: _networkServices(),
                ),
                Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.borderOf(context)),
                DoctorHomeServicesSection(
                  title: 'Clinical tools',
                  services: _clinicalServices(),
                ),
                Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.borderOf(context)),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: ColoredBox(
              color: AppColors.surfaceOf(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DoctorHomeSectionHeader(
                    title: 'Today\'s patients',
                    subtitle:
                        'Patients scheduled for ${DateFormat('EEE, dd MMM').format(_selectedDate)}',
                    secondaryActionLabel: 'Calendar',
                    secondaryActionSubtitle:
                        DateFormat('d MMM yyyy').format(_selectedDate),
                    onSecondaryAction: _openCalendarPopup,
                    actionLabel: 'View all',
                    actionFilled: true,
                    onAction: _openTodaysAppointments,
                  ),
                  ListenableBuilder(
                    listenable: _store,
                    builder: (context, _) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: DoctorDatePatientList(
                        selectedDate: _selectedDate,
                        appointments: _store.appointmentsForDoctorOnDate(
                          DoctorSession.loggedInDoctorId,
                          _selectedDate,
                        ),
                        onViewAppointment: _viewAppointment,
                        onAccept: _acceptAppointment,
                        onAcceptFamily: _acceptFamilyAppointments,
                        onDecline: _declineAppointment,
                        onStart: _startConsultation,
                        onCancel: _cancelAppointment,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Divider(
                height: 1, thickness: 1, color: AppColors.borderOf(context)),
          ),
          SliverToBoxAdapter(
            child: DoctorHomeSectionHeader(
              title: 'Upcoming appointments',
              subtitle: 'Your next scheduled visits',
              actionLabel: 'View all',
              onAction: () => widget.onOpenAppointments?.call(1),
            ),
          ),
          _UpcomingSliverList(
            store: _store,
            onViewAppointment: _viewAppointment,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  void _openCalendarPopup() {
    DoctorAppointmentCalendar.showPopup(
      context,
      doctorId: DoctorSession.loggedInDoctorId,
      selectedDate: _selectedDate,
      onDateSelected: (date) => setState(() => _selectedDate = date),
    );
  }

  void _openTodaysAppointments() {
    final date = _selectedDate;
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final title = isToday
        ? 'Today\'s Appointments'
        : 'Appointments · ${DateFormat('EEE, d MMM yyyy').format(date)}';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FilteredAppointmentsScreen(
          title: title,
          tab: AppointmentListTab.today,
          selectedDate: date,
        ),
      ),
    );
  }

  Future<void> _openAddNewPatient() async {
    await WalkInPatientSheet.show(context);
  }

  Future<void> _acceptAppointment(Appointment appointment) async {
    try {
      await _store.acceptAppointment(appointment.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(e,
                fallback:
                    "Couldn't accept this appointment. Please check your connection and try again."),
          ),
        ),
      );
      return;
    }
  }

  Future<void> _acceptFamilyAppointments(List<Appointment> members) async {
    final pending = members
        .where((m) => m.status == AppointmentStatus.pendingRequest)
        .map((m) => m.id)
        .toList();
    if (pending.isEmpty) return;

    try {
      await _store.acceptAppointments(pending);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(e,
                fallback:
                    "Couldn't accept these appointments. Please check your connection and try again."),
          ),
        ),
      );
      return;
    }
  }

  Future<void> _declineAppointment(Appointment appointment) async {
    try {
      await _store.declineAppointment(appointment.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(e,
                fallback:
                    "Couldn't decline this appointment. Please check your connection and try again."),
          ),
        ),
      );
      return;
    }
  }

  Future<void> _startConsultation(Appointment appointment) async {
    try {
      await _store.updateDoctorStatus(
          appointment.id, AppointmentStatus.inProgress);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(
              e,
              fallback:
                  "Couldn't start consultation. Please check your connection and try again.",
            ),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final record = _store.findRecordById(appointment.id);
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
    ClinicalToolsShell.open(
      context,
      patient: PatientClinicalContext(
        patientName: appointment.patientName,
        age: appointment.age,
        gender: AppConstants.normalizePatientGender(appointment.gender),
        weightKg: weight,
        patientId: patientId,
        appointmentId: appointment.id,
      ),
      initialTab: 0,
    );
  }

  void _cancelAppointment(Appointment appointment) {
    DoctorAppointmentActions.cancel(
      context,
      appointment: appointment,
      reason: 'Cancelled from today\'s queue',
    );
  }

  void _viewAppointment(Appointment appointment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentDetailScreen(
            isDoctorView: true, appointment: appointment),
      ),
    );
  }

  DoctorStats _statsForDoctor() {
    final doctorId = DoctorSession.loggedInDoctorId;
    final appointments = _store.doctorAppointments(doctorId);

    return DoctorStats(
      todaysAppointments: AppointmentFilters.apply(
        source: appointments,
        tab: AppointmentListTab.today,
      ).length,
      pending: AppointmentFilters.apply(
        source: appointments,
        tab: AppointmentListTab.pending,
      ).length,
      completed: AppointmentFilters.apply(
        source: appointments,
        tab: AppointmentListTab.completed,
      ).length,
    );
  }
}

/// Isolated sliver that rebuilds ONLY itself when the store changes,
/// instead of forcing the entire DoctorHomeScreen to repaint.
class _UpcomingSliverList extends StatelessWidget {
  const _UpcomingSliverList({
    required this.store,
    this.onViewAppointment,
  });

  final SharedAppointmentsStore store;
  final void Function(Appointment)? onViewAppointment;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final upcoming =
            store.upcomingForDoctor(DoctorSession.loggedInDoctorId);
        if (upcoming.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: const DoctorUpcomingAppointmentsList(appointments: []),
            ),
          );
        }

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: DoctorUpcomingAppointmentsList(
              appointments: upcoming,
              onViewAppointment: onViewAppointment,
            ),
          ),
        );
      },
    );
  }
}
