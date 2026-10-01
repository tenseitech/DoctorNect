import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/profile_action_guard.dart';
import '../../../core/enums/user_type.dart';
import '../../../core/firebase/models/doctor_lab_order.dart';
import '../../../core/session/lab_session.dart';
import '../../../core/theme/app_colors.dart';
import '../data/lab_worklist_store.dart';
import '../widgets/lab_report_upload_sheet.dart';
import '../../promoted_ads/screens/promoted_ads_management_screen.dart';
import '../../../widgets/verification_status_banner.dart';
import '../../../widgets/shell/role_empty_state.dart';
import '../../../core/theme/app_typography.dart';

String labOrderStatusLabel(String status) => switch (status) {
      'ordered' => 'New',
      'requested' => 'New request',
      'confirmed' => 'Confirmed',
      'declined' => 'Declined',
      'processing' => 'Processing',
      'completed' => 'Completed',
      _ => status,
    };

Color labOrderStatusColor(String status) => switch (status) {
      'ordered' => AppColors.labPurple,
      'requested' => AppColors.labPurple,
      'confirmed' => AppColors.labPurple,
      'declined' => AppColors.error,
      'processing' => Colors.orange,
      'completed' => AppColors.pharmacyGreen,
      _ => AppColors.textSecondary,
    };

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDay(DateTime a, DateTime b) => _dateOnly(a) == _dateOnly(b);

bool _isCompletedOrder(DoctorLabOrder order) => order.status == 'completed';

String _labDoctorLabel(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Doctor';
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('dr.') || lower.startsWith('dr ')) return trimmed;
  return 'Dr. $trimmed';
}

DoctorLabOrder _bookingToOrder(LabBookingRecord b) {
  final isWalkIn = b.collectionType == 'walkIn';
  return DoctorLabOrder(
    orderId: b.bookingId,
    doctorId: '',
    doctorName: '',
    patientId: b.patientId,
    patientName: b.patientName,
    patientAge: 0,
    testIds: const [],
    testNames: b.allTestNames,
    createdAt: b.dateTime,
    labId: b.labId,
    labName: b.labName,
    source: isWalkIn ? 'walkin' : 'patient',
    status: b.status,
  );
}

String _sourceLabel(String source) => switch (source) {
      'walkin' => 'Walk-in',
      'patient' => 'Patient',
      _ => 'Doctor',
    };

Color _sourceColor(String source) => switch (source) {
      'walkin' => Colors.orange,
      'patient' => const Color(0xFF2563EB),
      _ => const Color(0xFF059669),
    };

String _orderSubtitle(DoctorLabOrder order) {
  final parts = <String>[];
  if (order.patientAge > 0) parts.add('${order.patientAge} yrs');
  if (order.doctorName.trim().isNotEmpty) {
    parts.add(_labDoctorLabel(order.doctorName));
  }
  parts.add(DateFormat('hh:mm a').format(order.createdAt));
  return parts.join(' · ');
}

class LabOrdersTab extends StatefulWidget {
  const LabOrdersTab({super.key});

  @override
  State<LabOrdersTab> createState() => _LabOrdersTabState();
}

class _LabOrdersTabState extends State<LabOrdersTab>
    with TickerProviderStateMixin {
  late final TabController _orderStatusTabController;
  final _searchController = TextEditingController();

  DateTime _selectedDate = _dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _orderStatusTabController = TabController(length: 2, vsync: this);
    _orderStatusTabController.addListener(() {
      if (!_orderStatusTabController.indexIsChanging) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
  }

  @override
  void dispose() {
    _orderStatusTabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _updateOrderStatus(
    BuildContext context,
    DoctorLabOrder order,
    String status,
  ) async {
    if (!ProfileActionGuard.isAllowed(UserType.lab)) {
      ProfileActionGuard.showPopup(context, UserType.lab);
      return;
    }
    try {
      final isBooking = order.source == 'walkin' || order.source == 'patient';
      if (isBooking) {
        // Find the original grouped booking to get all linked IDs
        final booking = LabWorklistStore.instance.bookings
            .where((b) => b.bookingId == order.orderId)
            .firstOrNull;
        final allIds = booking?.linkedBookingIds ?? [order.orderId];
        // Update all linked booking docs in Firestore
        await Future.wait(
          allIds.map(
            (id) => FirestoreService.instance.labBooking.updateBookingStatus(
              id,
              status,
            ),
          ),
        );
        LabWorklistStore.instance.updateBookingStatusLocal(
          order.orderId,
          status,
        );
      } else {
        await FirestoreService.instance.labOrder.updateOrderStatus(
          order.orderId,
          status,
        );
        LabWorklistStore.instance.updateOrderStatusLocal(order.orderId, status);
      }
    } catch (_) {
      if (!context.mounted) return;
      AppToast.info(
        context,
        'Could not update order status. Please try again.',
      );
    }
  }

  Future<void> _refreshAll() async {
    final labId = LabSession.loggedInLabId;
    if (labId.isEmpty) return;
    final page = await FirestoreService.instance.labOrder.fetchForLab(
      labId,
      preferCache: false,
    );
    LabWorklistStore.instance.mergeOrders(page.items);
    final bookings = await FirestoreService.instance.labBooking.fetchForLab(
      labId,
    );
    LabWorklistStore.instance.mergeBookings(bookings);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: AppColors.labPurple),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = _dateOnly(picked));
  }

  void _goToToday() =>
      setState(() => _selectedDate = _dateOnly(DateTime.now()));

  List<DoctorLabOrder> _ordersForSelectedDate() {
    var orders = LabWorklistStore.instance.orders
        .where((o) => _isSameDay(o.createdAt, _selectedDate))
        .toList();
    // Merge walk-in and patient bookings into the unified list
    final bookingOrders = LabWorklistStore.instance.bookings
        .where((b) => _isSameDay(b.dateTime, _selectedDate))
        .map(_bookingToOrder)
        .toList();
    orders.addAll(bookingOrders);
    final search = _searchController.text.trim().toLowerCase();
    if (search.isNotEmpty) {
      orders = orders
          .where(
            (o) =>
                o.patientName.toLowerCase().contains(search) ||
                o.doctorName.toLowerCase().contains(search) ||
                o.testNames.any((t) => t.toLowerCase().contains(search)),
          )
          .toList();
    }
    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return orders;
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(_selectedDate, DateTime.now());

    return ListenableBuilder(
      listenable: LabWorklistStore.instance,
      builder: (context, _) {
        final dayOrders = _ordersForSelectedDate();
        final newOrders =
            dayOrders.where((o) => !_isCompletedOrder(o)).toList();
        final completedOrders = dayOrders.where(_isCompletedOrder).toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const VerificationStatusBanner(role: UserType.lab),
                _LabDayStatsHeader(
                  selectedDate: _selectedDate,
                  isToday: isToday,
                  onToday: _goToToday,
                  onPickDate: _pickDate,
                  wide: wide,
                  newCount: newOrders.length,
                  doneCount: completedOrders.length,
                ),
                Expanded(
                  child: _DoctorOrdersPanel(
                    newOrders: newOrders,
                    completedOrders: completedOrders,
                    selectedDate: _selectedDate,
                    searchController: _searchController,
                    orderStatusTabController: _orderStatusTabController,
                    onSearchChanged: () => setState(() {}),
                    onRefresh: _refreshAll,
                    onUpdateStatus: _updateOrderStatus,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _LabDayStatsHeader extends StatelessWidget {
  const _LabDayStatsHeader({
    required this.selectedDate,
    required this.isToday,
    required this.onToday,
    required this.onPickDate,
    required this.wide,
    required this.newCount,
    required this.doneCount,
  });

  final DateTime selectedDate;
  final bool isToday;
  final VoidCallback onToday;
  final VoidCallback onPickDate;
  final bool wide;
  final int newCount;
  final int doneCount;

  Widget _buildStatBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = isToday
        ? 'Today · ${DateFormat('EEE, dd MMM').format(selectedDate)}'
        : DateFormat('EEE, dd MMM yyyy').format(selectedDate);

    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 12, wide ? 24 : 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.labPurple, Color(0xFF6D28D9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: wide
          ? Row(
              children: [
                Text(
                  'Test Orders',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                _buildStatBadge(TablerIcons.flask, '$newCount New'),
                const SizedBox(width: 8),
                _buildStatBadge(Icons.check_circle_outline, '$doneCount Done'),
                const Spacer(),
                if (!isToday)
                  TextButton(
                    onPressed: onToday,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    child: Text(
                      'Today',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: AppTypography.labelMedium,
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: onPickDate,
                  icon: const Icon(
                    Icons.calendar_month_outlined,
                    color: Colors.white,
                  ),
                  tooltip: 'Pick date',
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: () {
                    PromotedAdsManagementScreen.open(
                      context,
                      providerType: 'lab',
                      providerId: LabSession.loggedInLabId,
                      providerEmail: '',
                      providerContact: '',
                      isVerified: true,
                    );
                  },
                  icon: const Icon(
                    Icons.campaign_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Promote Ad',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dateLabel,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodySmall,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                    if (!isToday)
                      TextButton(
                        onPressed: onToday,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                        ),
                        child: Text(
                          'Today',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: AppTypography.labelSmall,
                          ),
                        ),
                      ),
                    IconButton(
                      onPressed: onPickDate,
                      icon: const Icon(
                        Icons.calendar_month_outlined,
                        size: 20,
                        color: Colors.white,
                      ),
                      tooltip: 'Pick date',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () {
                        PromotedAdsManagementScreen.open(
                          context,
                          providerType: 'lab',
                          providerId: LabSession.loggedInLabId,
                          providerEmail: '',
                          providerContact: '',
                          isVerified: true,
                        );
                      },
                      icon: const Icon(
                        Icons.campaign_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      tooltip: 'Promote Ad',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatBadge(TablerIcons.flask, '$newCount New'),
                    const SizedBox(width: 8),
                    _buildStatBadge(
                      Icons.check_circle_outline,
                      '$doneCount Done',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _DoctorOrdersPanel extends StatelessWidget {
  const _DoctorOrdersPanel({
    required this.newOrders,
    required this.completedOrders,
    required this.selectedDate,
    required this.searchController,
    required this.orderStatusTabController,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onUpdateStatus,
  });

  final List<DoctorLabOrder> newOrders;
  final List<DoctorLabOrder> completedOrders;
  final DateTime selectedDate;
  final TextEditingController searchController;
  final TabController orderStatusTabController;
  final VoidCallback onSearchChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function(
    BuildContext context,
    DoctorLabOrder order,
    String status,
  ) onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('dd MMM yyyy').format(selectedDate);
    final wide = MediaQuery.of(context).size.width >= 900;
    final controlBar = Container(
      padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: wide ? 240 : 160,
            child: _LabOrderTabSwitcher(
              controller: orderStatusTabController,
              newCount: newOrders.length,
              completedCount: completedOrders.length,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LabSearchField(
              controller: searchController,
              onChanged: onSearchChanged,
            ),
          ),
        ],
      ),
    );

    final tabViews = [
      _orderList(
        context,
        newOrders,
        isNewTab: true,
        dateLabel: dateLabel,
        emptyTitle: 'No new orders',
        emptySubtitle: 'Orders and bookings for $dateLabel will appear here.',
      ),
      _orderList(
        context,
        completedOrders,
        isNewTab: false,
        dateLabel: dateLabel,
        emptyTitle: 'No completed orders',
        emptySubtitle: 'Completed orders for $dateLabel will be listed here.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        controlBar,
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            color: AppColors.labPurple,
            child: TabBarView(
              controller: orderStatusTabController,
              children: tabViews,
            ),
          ),
        ),
      ],
    );
  }

  Widget _orderList(
    BuildContext context,
    List<DoctorLabOrder> orders, {
    required bool isNewTab,
    required String dateLabel,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    if (orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          RoleEmptyState(
            icon: Icons.science_outlined,
            title: emptyTitle,
            subtitle: emptySubtitle,
            accentColor: AppColors.labPurple,
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final order = orders[i];
        final isBooking = order.source == 'walkin' || order.source == 'patient';
        // Find the original booking record for report sharing
        final booking = isBooking
            ? LabWorklistStore.instance.bookings
                .where((b) => b.bookingId == order.orderId)
                .firstOrNull
            : null;

        final bool hasReport = isBooking
            ? (booking?.hasReport ?? false)
            : (order.reportStorageUrl != null &&
                order.reportStorageUrl!.isNotEmpty);

        return _LabOrderTile(
          order: order,
          isNewTab: isNewTab,
          hasReport: hasReport,
          onUpdateStatus: (status) => onUpdateStatus(context, order, status),
          onShareReport: (isBooking && booking == null)
              ? null
              : () async {
                  await LabReportUploadSheet.show(
                    context,
                    booking: isBooking ? booking : null,
                    order: !isBooking ? order : null,
                  );
                },
        );
      },
    );
  }
}

typedef _LabOrderTabSwitcher = LabOrderTabSwitcher;

class LabOrderTabSwitcher extends StatelessWidget {
  const LabOrderTabSwitcher({
    super.key,
    required this.controller,
    required this.newCount,
    required this.completedCount,
  });

  final TabController controller;
  final int newCount;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final trackColor = isDark
        ? AppColors.darkSurface
        : const Color(0xFFE2E8F0).withValues(alpha: 0.5);
    final trackBorder = isDark
        ? Border.all(
            color: AppColors.darkBorder.withValues(alpha: 0.6),
            width: 1,
          )
        : Border.all(
            color: const Color(0xFFCBD5E1).withValues(alpha: 0.5),
            width: 1,
          );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(12),
            border: trackBorder,
          ),
          child: Row(
            children: [
              Expanded(
                child: _OrderTabPill(
                  label: 'New',
                  count: newCount,
                  selected: controller.index == 0,
                  accentColor: AppColors.labPurple,
                  onTap: () => controller.animateTo(0),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _OrderTabPill(
                  label: 'Done',
                  count: completedCount,
                  selected: controller.index == 1,
                  accentColor: AppColors.labPurple,
                  onTap: () => controller.animateTo(1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderTabPill extends StatelessWidget {
  const _OrderTabPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    // Active pill background: Lab accent at ~22% alpha in dark mode, white in light mode
    final activeBg = isDark
        ? accentColor.withValues(alpha: 0.22)
        : AppColors.surfaceOf(context);

    // Active label color: High contrast white in dark mode, accentColor in light mode
    final labelColor = selected
        ? (isDark ? Colors.white : accentColor)
        : AppColors.textSecondaryOf(context);

    // Badge background
    final badgeBg = selected
        ? (isDark
            ? accentColor.withValues(alpha: 0.35)
            : accentColor.withValues(alpha: 0.12))
        : (isDark
            ? AppColors.darkTextSecondary.withValues(alpha: 0.15)
            : AppColors.textSecondaryOf(context).withValues(alpha: 0.12));

    // Badge text color
    final badgeTextColor = selected
        ? (isDark ? Colors.white : accentColor)
        : AppColors.textSecondaryOf(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected && isDark
                ? Border.all(
                    color: accentColor.withValues(alpha: 0.35),
                    width: 1,
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.25)
                          : Colors.black.withValues(alpha: 0.06),
                      blurRadius: isDark ? 6 : 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: badgeTextColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showOrderDetails(BuildContext context, DoctorLabOrder order) {
  showDialog(
    context: context,
    builder: (context) {
      final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
      return Dialog(
        backgroundColor: AppColors.surfaceOf(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Order Details',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.headlineSmall,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Patient Info',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          order.patientName,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.headlineSmall,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          order.patientAge > 0
                              ? '${order.patientAge} years old'
                              : 'Age: Not provided',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyMedium,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (order.source != 'walkin') ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.labPurple.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.labPurple.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Referred By',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              fontWeight: FontWeight.w600,
                              color: AppColors.labPurple,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.medical_services_outlined,
                                size: 16,
                                color: AppColors.labPurple,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Dr. ${order.doctorName}',
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.bodyLarge,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Tests Ordered (${order.testNames.length})',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...order.testNames.map(
                    (test) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.science_outlined,
                              size: 16,
                              color: AppColors.labPurple,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              test,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.bodyMedium,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Order Time:',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a')
                            .format(order.createdAt),
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

typedef _LabSearchField = LabSearchField;

class LabSearchField extends StatelessWidget {
  const LabSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final borderColor = isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0);

    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      style: GoogleFonts.inter(
        fontSize: AppTypography.bodySmall,
        color: AppColors.textPrimaryOf(context),
      ),
      decoration: InputDecoration(
        hintText: 'Search',
        hintStyle: GoogleFonts.inter(
          fontSize: AppTypography.bodySmall,
          color: AppColors.textSecondaryOf(context),
        ),
        isDense: true,
        prefixIcon: Icon(
          Icons.search,
          size: 18,
          color: AppColors.textSecondaryOf(context),
        ),
        filled: true,
        fillColor: AppColors.surfaceOf(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.labPurple),
        ),
      ),
    );
  }
}

class _LabOrderTile extends StatelessWidget {
  const _LabOrderTile({
    required this.order,
    required this.isNewTab,
    required this.onUpdateStatus,
    this.hasReport = false,
    this.onShareReport,
  });

  final DoctorLabOrder order;
  final bool isNewTab;
  final bool hasReport;
  final void Function(String status) onUpdateStatus;
  final VoidCallback? onShareReport;

  @override
  Widget build(BuildContext context) {
    final statusColor = labOrderStatusColor(order.status);
    final gradient = isNewTab
        ? const [AppColors.labPurple, Color(0xFF7C3AED)]
        : const [Color(0xFF059669), Color(0xFF047857)];

    final bool showReport = onShareReport != null &&
        order.status != 'declined' &&
        order.status != 'requested';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBorder = isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showOrderDetails(context, order),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DateBadge(date: order.createdAt, gradient: gradient),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  order.patientName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.bodyMedium,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _SourceBadge(source: order.source),
                              const SizedBox(width: 6),
                              PopupMenuButton<String>(
                                initialValue: order.status,
                                onSelected: onUpdateStatus,
                                tooltip: 'Update Status',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        labOrderStatusLabel(order.status),
                                        style: GoogleFonts.inter(
                                          fontSize: AppTypography.labelSmall,
                                          fontWeight: FontWeight.w700,
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        size: 14,
                                        color: statusColor,
                                      ),
                                    ],
                                  ),
                                ),
                                itemBuilder: (context) => [
                                  'ordered',
                                  'requested',
                                  'confirmed',
                                  'processing',
                                  'completed',
                                  'declined',
                                ]
                                    .map(
                                      (status) => PopupMenuItem<String>(
                                        value: status,
                                        child: Text(
                                          labOrderStatusLabel(status),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _orderSubtitle(order),
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkBackground
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.science_outlined,
                        size: 16,
                        color: AppColors.textSecondaryOf(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order.testNames.join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showReport && hasReport) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 15,
                        color: AppColors.pharmacyGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Report sent',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.pharmacyGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ] else if (showReport && !hasReport) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onShareReport,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Share report'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.labPurple,
                      minimumSize: const Size(double.infinity, 42),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date, required this.gradient});

  final DateTime date;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppColors.darkBackground : const Color(0xFFF8FAFC);
    final borderColor = isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0);

    return Container(
      width: 50,
      height: 56,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 17,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
            ),
            alignment: Alignment.center,
            child: Text(
              DateFormat('MMM').format(date).toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('dd').format(date),
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final label = _sourceLabel(source);
    final color = _sourceColor(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
