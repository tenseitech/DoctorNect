import 'package:flutter/material.dart';

import '../../../core/data/shared_appointments_store.dart';
import '../../../core/theme/app_colors.dart';
import '../profile/widgets/patient_profile_form_styles.dart';
import '../search/doctor_search_screen.dart';
import 'package:medibond/features/shared/screens/appointment_detail_screen.dart';
import 'data/patient_appointment_filters.dart';
import 'models/patient_appointment_models.dart';
import '../widgets/patient_shell_tab.dart';
import 'widgets/visit_appointment_tile.dart';

class PatientAppointmentsScreen extends StatefulWidget {
  const PatientAppointmentsScreen({super.key, this.openedFromProfile = false});

  final bool openedFromProfile;

  @override
  State<PatientAppointmentsScreen> createState() =>
      _PatientAppointmentsScreenState();
}

class _PatientAppointmentsScreenState extends State<PatientAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _store = SharedAppointmentsStore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  List<PatientAppointment> get _all => _store.patientAppointments();

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _openDetail(PatientAppointment a) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AppointmentDetailScreen(appointment: a)),
    );
  }

  void _openDoctorSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DoctorSearchScreen()),
    );
  }

  List<Widget> _visitTiles(List<PatientAppointment> items) {
    return [
      for (var i = 0; i < items.length; i++)
        VisitAppointmentTile(
          appointment: items[i],
          showDivider: i < items.length - 1,
          onTap: () => _openDetail(items[i]),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = PatientAppointmentFilters.upcoming(_all);
    final completed = PatientAppointmentFilters.completed(_all);
    final cancelled = PatientAppointmentFilters.cancelled(_all);

    final tabBodies = [
      PatientShellTabList(
        empty: PatientTabEmptyState(
          icon: Icons.event_available_outlined,
          title: 'No upcoming visits',
          message: 'Book a doctor appointment and it will show up here.',
          actionLabel: 'Find a doctor',
          onAction: _openDoctorSearch,
        ),
        children: _visitTiles(upcoming),
      ),
      PatientShellTabList(
        empty: PatientTabEmptyState(
          icon: Icons.history,
          title: 'No completed visits',
          message: 'Your past appointments will appear here after your visit.',
        ),
        children: _visitTiles(completed),
      ),
      PatientShellTabList(
        empty: PatientTabEmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No cancelled visits',
          message: 'Cancelled appointments will be listed here.',
        ),
        children: _visitTiles(cancelled),
      ),
    ];

    if (widget.openedFromProfile) {
      return Scaffold(
        backgroundColor: AppColors.cardBgOf(context),
        appBar: PatientProfileFormStyles.profileAppBar('My Appointments',
            context: context),
        body: Column(
          children: [
            PatientSegmentedTabBar(
              controller: _tabController,
              labels: [
                'Upcoming (${upcoming.length})',
                'Completed (${completed.length})',
                'Cancelled (${cancelled.length})',
              ],
              accentColor: Color(0xFF117554),
            ),
            Divider(
                height: 1, thickness: 1, color: AppColors.borderOf(context)),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: tabBodies,
              ),
            ),
          ],
        ),
      );
    }

    return PatientShellTabPage(
      title: 'Appointments',
      subtitle: 'Upcoming, completed & cancelled appointments',
      tabController: _tabController,
      tabLabels: [
        'Upcoming (${upcoming.length})',
        'Completed (${completed.length})',
        'Cancelled (${cancelled.length})',
      ],
      tabBodies: tabBodies,
      accentColor: const Color(0xFF117554),
    );
  }
}
