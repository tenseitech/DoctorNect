import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_colors.dart';
import '../records/data/patient_lab_booking_store.dart';
import '../records/widgets/patient_blood_test_sheet.dart';
import '../widgets/patient_shell_tab.dart';
import 'data/patient_lab_booking_filters.dart';
import 'widgets/lab_booking_tile.dart';

class PatientLabBookingsScreen extends StatefulWidget {
  const PatientLabBookingsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<PatientLabBookingsScreen> createState() =>
      _PatientLabBookingsScreenState();
}

class _PatientLabBookingsScreenState extends State<PatientLabBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _store = PatientLabBookingStore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _store.addListener(_onStoreChanged);
    _refresh();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return;
    await _store.refreshForPatient(patientId, preferCache: false);
  }

  List<LabBookingRecord> _bookings() =>
      _store.forPatient(PatientSession.loggedInPatientId);

  void _openBooking(LabBookingRecord booking) {
    PatientBloodTestSheet.show(context, booking);
  }

  @override
  Widget build(BuildContext context) {
    final all = _bookings();
    final upcoming = PatientLabBookingFilters.upcoming(all);
    final history = PatientLabBookingFilters.history(all);
    final compact = ResponsiveLayout.isCompact(context);
    final maxWidth =
        ResponsiveLayout.contentMaxWidth(context).clamp(0.0, 720.0);

    final tabBodies = [
      _LabBookingsTabBody(
        bookings: upcoming,
        onRefresh: _refresh,
        onTap: _openBooking,
        empty: const PatientTabEmptyState(
          icon: Icons.biotech_outlined,
          title: 'No lab bookings',
          message:
              'Book a test from the Lab tab and your requests will appear here.',
          accentColor: AppColors.labPurple,
        ),
      ),
      _LabBookingsTabBody(
        bookings: history,
        onRefresh: _refresh,
        onTap: _openBooking,
        empty: const PatientTabEmptyState(
          icon: Icons.history,
          title: 'No booking history',
          message: 'Completed and past lab bookings will show up here.',
          accentColor: AppColors.labPurple,
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: AppColors.surfaceOf(context),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LabBookingsHeader(
                    compact: compact,
                    onBack: () => Navigator.pop(context),
                  ),
                  PatientSegmentedTabBar(
                    controller: _tabController,
                    labels: [
                      compact
                          ? 'Bookings (${upcoming.length})'
                          : 'Lab bookings (${upcoming.length})',
                      'History (${history.length})',
                    ],
                    accentColor: AppColors.labPurple,
                  ),
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.borderOf(context)),
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: TabBarView(
                  controller: _tabController,
                  children: tabBodies,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabBookingsHeader extends StatelessWidget {
  const _LabBookingsHeader({
    required this.compact,
    required this.onBack,
  });

  final bool compact;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final hPad = compact ? 4.0 : 12.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, compact ? 4 : 8, compact ? 12 : 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textPrimaryOf(context),
            tooltip: 'Back',
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                  top: compact ? 6 : 10, right: compact ? 0 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bookings & History',
                    style: GoogleFonts.inter(
                      fontSize: compact ? 20 : 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upcoming tests and past lab bookings',
                    style: GoogleFonts.inter(
                      fontSize: compact ? 12 : 13,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabBookingsTabBody extends StatelessWidget {
  const _LabBookingsTabBody({
    required this.bookings,
    required this.onRefresh,
    required this.onTap,
    required this.empty,
  });

  final List<LabBookingRecord> bookings;
  final Future<void> Function() onRefresh;
  final ValueChanged<LabBookingRecord> onTap;
  final PatientTabEmptyState empty;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return ColoredBox(color: AppColors.surfaceOf(context), child: empty);
    }

    final compact = ResponsiveLayout.isCompact(context);
    final hPad = compact ? 16.0 : 20.0;
    final vPad = compact ? 12.0 : 16.0;

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: RefreshIndicator(
        color: AppColors.labPurple,
        onRefresh: onRefresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              hPad, vPad, hPad, vPad + MediaQuery.paddingOf(context).bottom),
          itemCount: bookings.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final booking = bookings[index];
            return LabBookingTile(
              booking: booking,
              onTap: () => onTap(booking),
            );
          },
        ),
      ),
    );
  }
}
