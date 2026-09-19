import '../../core/firebase/firestore_service.dart';
// ignore_for_file: unused_element_parameter
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/firebase/ambulance_auth_helper.dart';
import '../../core/firebase/firestore_paths.dart';
import '../../core/notifications/ambulance_push_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/session/ambulance_session.dart';
import '../../core/theme/app_colors.dart';
import 'widgets/ambulance_page_layout.dart';
import 'data/ambulance_booking_sync.dart';
import 'data/ambulance_store.dart';
import 'models/ambulance_models.dart';
import '../promoted_ads/screens/promoted_ads_management_screen.dart';
import '../../core/theme/app_typography.dart';
// FIXED: online/offline toggle on the post-login dashboard

class AmbulanceDriverHomeScreen extends StatefulWidget {
  const AmbulanceDriverHomeScreen({super.key});

  @override
  AmbulanceDriverHomeScreenState createState() => AmbulanceDriverHomeScreenState();
}

enum AmbulanceDriverTab { pending, accepted, completed, cancelled }

class AmbulanceDriverHomeScreenState extends State<AmbulanceDriverHomeScreen> {
  AmbulanceDriverTab _selectedTab = AmbulanceDriverTab.pending;

  static const _accent = Color(0xFFDC2626);

  void openPendingTab() => setState(() => _selectedTab = AmbulanceDriverTab.pending);

  @override
  void initState() {
    super.initState();
    _startSync();
    _openPendingFromPushIfNeeded();
  }

  void _openPendingFromPushIfNeeded() {
    final broadcastId = AmbulancePushService.pendingOpenBroadcastId;
    if (broadcastId == null || broadcastId.isEmpty) return;
    AmbulancePushService.pendingOpenBroadcastId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedTab = AmbulanceDriverTab.pending);
    });
  }

  Future<void> _startSync() async {
    final driverId = AmbulanceSession.loggedInAmbulanceId;
    if (driverId.isEmpty) return;

    await AmbulanceAuthHelper.ensureSignedIn();
    await FirestoreService.instance.ambulance.linkDriverAuth(driverId);
    
    // Self-healing: pull missing ratings from broadcasts for old trips
    try {
      final firestore = FirebaseFirestore.instance;
      final reqs = await firestore
          .collection(FirestorePaths.ambulanceRequests)
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'completed')
          .get();
      for (final doc in reqs.docs) {
        if (doc.data()['rating'] == null) {
          final broadcastId = doc.data()['broadcastId'] as String?;
          if (broadcastId != null) {
            final bDoc = await firestore.collection(FirestorePaths.ambulanceBroadcasts).doc(broadcastId).get();
            if (bDoc.exists && bDoc.data()?['rating'] != null) {
              await doc.reference.update({
                'rating': bDoc.data()!['rating'],
                'review': bDoc.data()!['review'],
                'ratedAt': bDoc.data()!['ratedAt'],
              });
            }
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;
    AmbulanceBookingSync.instance.watchDriverRequests(driverId);
  }

  @override
  void dispose() {
    AmbulanceBookingSync.instance.stopDriverWatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ambulanceId = AmbulanceSession.loggedInAmbulanceId;
    final store = AmbulanceStore.instance;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final bookings = store.bookings;
        final pending = bookings
            .where((b) => store.isPendingForDriver(b, ambulanceId))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final mine = bookings
            .where(
              (b) =>
                  b.isAccepted &&
                  !b.isCompleted &&
                  b.acceptedAmbulanceId == ambulanceId,
            )
            .toList();
        final completed = bookings
            .where((b) =>
                b.isCompleted &&
                b.acceptedAmbulanceId == ambulanceId)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final cancelled = bookings
            .where((b) =>
                (b.isCancelled &&
                    (b.acceptedAmbulanceId == ambulanceId ||
                        (b.acceptedAmbulanceId == null &&
                            b.rawStatus == 'rejected'))) ||
                store.isDriverRejectedBookingView(b, ambulanceId))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RequestsHeader(
              pendingCount: pending.length,
              acceptedCount: mine.length,
              completedCount: completed.length,
            ),
            Expanded(
              child: AmbulancePageLayout(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TripTabSwitcher(
                      pendingCount: pending.length,
                      acceptedCount: mine.length,
                      completedCount: completed.length,
                      cancelledCount: cancelled.length,
                      selected: _selectedTab,
                      onSelect: (tab) => setState(() => _selectedTab = tab),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: RefreshIndicator(
                        color: _accent,
                        onRefresh: () async {
                          await _startSync();
                        },
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            ..._buildSelectedTabContent(
                              context: context,
                              tab: _selectedTab,
                              pending: pending,
                              mine: mine,
                              completed: completed,
                              cancelled: cancelled,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildSelectedTabContent({
    required BuildContext context,
    required AmbulanceDriverTab tab,
    required List<AmbulanceBooking> pending,
    required List<AmbulanceBooking> mine,
    required List<AmbulanceBooking> completed,
    required List<AmbulanceBooking> cancelled,
  }) {
    switch (tab) {
      case AmbulanceDriverTab.pending:
        return [
          _SectionHeader(
            title: 'New requests',
            count: pending.length,
            icon: Icons.notifications_active_outlined,
            color: const Color(0xFFEA580C),
          ),
          if (pending.isEmpty)
            const _EmptyHint(
              text: 'No pending requests right now.',
              icon: Icons.check_circle_outline,
            )
          else
            ...pending.map(
              (b) => _RequestCard(
                booking: b,
                showAccept: true,
                onAccept: () => _accept(context, b.id),
                onReject: () => _reject(context, b.id),
              ),
            ),
        ];
      case AmbulanceDriverTab.accepted:
        return [
          _SectionHeader(
            title: 'Accepted by you',
            count: mine.length,
            icon: Icons.check_circle_outlined,
            color: const Color(0xFF2563EB), // Blue for Accepted
          ),
          if (mine.isEmpty)
            const _EmptyHint(
              text: 'Your accepted trips will appear here.',
              icon: Icons.local_shipping_outlined,
            )
          else
            ...mine.map(
              (b) => _RequestCard(
                booking: b,
                showAccept: false,
                highlight: true,
                showComplete: true,
                onComplete: () => _completeTrip(context, b.id),
                showCancel: true,
                onCancel: () => _cancelTrip(context, b.id),
              ),
            ),
        ];
      case AmbulanceDriverTab.completed:
        return [
          _SectionHeader(
            title: 'Completed trips',
            count: completed.length,
            icon: Icons.history,
            color: const Color(0xFF16A34A), // Green for Completed
          ),
          if (completed.isEmpty)
            const _EmptyHint(
              text: 'Completed trips will appear here.',
              icon: Icons.history_outlined,
            )
          else
            ...completed.map(
              (b) => _RequestCard(
                booking: b,
                showAccept: false,
                isCompleted: b.isCompleted,
                isCancelled: b.isCancelled,
              ),
            ),
        ];
      case AmbulanceDriverTab.cancelled:
        return [
          _SectionHeader(
            title: 'Cancelled trips',
            count: cancelled.length,
            icon: Icons.cancel_outlined,
            color: const Color(0xFFDC2626),
          ),
          if (cancelled.isEmpty)
            const _EmptyHint(
              text: 'Cancelled trips will appear here.',
              icon: Icons.cancel_outlined,
            )
          else
            ...cancelled.map(
              (b) => _RequestCard(
                booking: b,
                showAccept: false,
                isCompleted: b.isCompleted,
                isCancelled: b.isCancelled,
              ),
            ),
        ];
    }
  }

  Future<void> _completeTrip(BuildContext context, String bookingId) async {
    final ok = await FirestoreService.instance.ambulance.completeBroadcast(
      broadcastId: bookingId,
      driverId: AmbulanceSession.loggedInAmbulanceId,
    );
    if (!context.mounted) return;
    if (ok) {
      setState(() => _selectedTab = AmbulanceDriverTab.completed);
    }
  }

  Future<void> _cancelTrip(BuildContext context, String bookingId) async {
    final ambulanceId = AmbulanceSession.loggedInAmbulanceId;
    if (ambulanceId.isEmpty) return;

    await AmbulanceAuthHelper.ensureSignedIn();
    await FirestoreService.instance.ambulance.linkDriverAuth(ambulanceId);

    final ok = await FirestoreService.instance.ambulance.cancelAcceptedBroadcast(
      broadcastId: bookingId,
      driverId: ambulanceId,
    );
    if (!context.mounted) return;
    if (ok) {
      setState(() => _selectedTab = AmbulanceDriverTab.cancelled);
    } else {
      final message = FirestoreService.instance.ambulance.lastCancelFailureUserMessage ??
          'Could not cancel this trip. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _reject(BuildContext context, String bookingId) async {
    final ambulanceId = AmbulanceSession.loggedInAmbulanceId;
    await FirestoreService.instance.ambulance.rejectBroadcast(
      broadcastId: bookingId,
      driverId: ambulanceId,
    );
  }

  Future<void> _accept(BuildContext context, String bookingId) async {
    final ambulanceId = AmbulanceSession.loggedInAmbulanceId;
    if (ambulanceId.isEmpty) return;

    await AmbulanceAuthHelper.ensureSignedIn();

    final ambulance = AmbulanceStore.instance.findAmbulance(ambulanceId) ??
        await FirestoreService.instance.ambulance.fetchAmbulanceById(ambulanceId);

    final ok = await FirestoreService.instance.ambulance.acceptBroadcast(
      broadcastId: bookingId,
      driverId: ambulanceId,
      ambulanceName: ambulance?.serviceName ?? AmbulanceSession.loggedInAmbulanceName,
    );
    if (!context.mounted) return;
    if (ok) {
      setState(() => _selectedTab = AmbulanceDriverTab.accepted);
    } else {
      final message =
          FirestoreService.instance.ambulance.lastAcceptFailureUserMessage ??
          'Could not accept this trip. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

// ── Requests Header ───────────────────────────────────────────────────────────

class _RequestsHeader extends StatelessWidget {
  const _RequestsHeader({
    required this.pendingCount,
    required this.acceptedCount,
    required this.completedCount,
  });

  final int pendingCount;
  final int acceptedCount;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip Requests',
                  style: GoogleFonts.inter(fontSize: AppTypography.headlineMedium, fontWeight: FontWeight.w700, color: AppColors.surfaceOf(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  '$pendingCount new · $acceptedCount active · $completedCount completed',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: AppColors.surfaceOf(context).withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () {
              final driverId = AmbulanceSession.loggedInAmbulanceId;
              final amb = AmbulanceStore.instance.findAmbulance(driverId);
              PromotedAdsManagementScreen.open(
                context,
                providerType: 'ambulance',
                providerId: driverId,
                providerEmail: amb?.username ?? '',
                providerContact: amb?.phone ?? '',
                isVerified: true,
              );
            },
            icon: const Icon(Icons.campaign_rounded, size: 16, color: Colors.white),
            label: const Text('Promote Ad', style: TextStyle(color: Colors.white, fontSize: AppTypography.labelMedium, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Trip Tab Switcher ─────────────────────────────────────────────────────────

class _TripTabSwitcher extends StatelessWidget {
  const _TripTabSwitcher({
    required this.pendingCount,
    required this.acceptedCount,
    required this.completedCount,
    required this.cancelledCount,
    required this.selected,
    required this.onSelect,
  });

  final int pendingCount;
  final int acceptedCount;
  final int completedCount;
  final int cancelledCount;
  final AmbulanceDriverTab selected;
  final ValueChanged<AmbulanceDriverTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _TripTabPill(
            label: 'New',
            count: pendingCount,
            selected: selected == AmbulanceDriverTab.pending,
            color: const Color(0xFFEA580C),
            onTap: () => onSelect(AmbulanceDriverTab.pending),
          ),
          _TripTabPill(
            label: 'Active',
            count: acceptedCount,
            selected: selected == AmbulanceDriverTab.accepted,
            color: const Color(0xFF2563EB),
            onTap: () => onSelect(AmbulanceDriverTab.accepted),
          ),
          _TripTabPill(
            label: 'Done',
            count: completedCount,
            selected: selected == AmbulanceDriverTab.completed,
            color: const Color(0xFF16A34A),
            onTap: () => onSelect(AmbulanceDriverTab.completed),
          ),
          _TripTabPill(
            label: 'Cancelled',
            count: cancelledCount,
            selected: selected == AmbulanceDriverTab.cancelled,
            color: const Color(0xFFDC2626),
            onTap: () => onSelect(AmbulanceDriverTab.cancelled),
          ),
        ],
      ),
    );
  }
}

class _TripTabPill extends StatelessWidget {
  const _TripTabPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.surfaceOf(context) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: selected
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Column(
              children: [
                Text(
                  '$count',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w800,
                    color: selected ? color : AppColors.textSecondaryOf(context),
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? color : AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String title;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: GoogleFonts.inter(fontSize: AppTypography.bodyLarge, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty Hint ────────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Request Card ──────────────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.booking,
    required this.showAccept,
    this.onAccept,
    this.onReject,
    this.highlight = false,
    this.alreadyTaken = false,
    this.showComplete = false,
    this.onComplete,
    this.showCancel = false,
    this.onCancel,
    this.isCompleted = false,
    this.isCancelled = false,
  });

  final AmbulanceBooking booking;
  final bool showAccept;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final bool highlight;
  final bool alreadyTaken;
  final bool showComplete;
  final VoidCallback? onComplete;
  final bool showCancel;
  final VoidCallback? onCancel;
  final bool isCompleted;
  final bool isCancelled;

  String _getCancelledByText() {
    final raw = booking.rawStatus;
    if (raw == 'rejected') return 'Cancelled by You';
    if (raw == 'taken') return 'Taken by another ambulance';
    if (raw == 'expired') return 'Request Expired';
    if (raw == 'cancelled') {
      if (booking.bookedByRole == AmbulanceBookedByRole.doctor) {
        return 'Cancelled by Doctor';
      } else {
        return 'Cancelled by Patient';
      }
    }
    return 'Cancelled';
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = isCompleted
        ? const Color(0xFF16A34A)
        : highlight
            ? const Color(0xFF2563EB)
            : alreadyTaken
                ? AppColors.borderOf(context)
                : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFEFF6FF) : AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor.withValues(alpha: highlight ? 0.3 : 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: highlight
                        ? const Color(0xFF2563EB).withValues(alpha: 0.1)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    highlight ? Icons.check_circle : Icons.person_pin_circle,
                    size: 20,
                    color: highlight
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.patientName,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        booking.pickupLocation,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (alreadyTaken)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Taken',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 14, color: AppColors.textSecondaryOf(context)),
                const SizedBox(width: 4),
                Text(
                  booking.contactPhone,
                  style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(width: 12),
                Icon(Icons.person_outline, size: 14, color: AppColors.textSecondaryOf(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'by ${booking.bookedByName}',
                    style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (booking.notes != null && booking.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes_outlined, size: 14, color: AppColors.textSecondaryOf(context)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      booking.notes!,
                      style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                    ),
                  ),
                ],
              ),
            ],
            if (booking.isAccepted && booking.acceptedAmbulanceName != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.check_circle, size: 14, color: Color(0xFF2563EB)),
                  const SizedBox(width: 4),
                  Text(
                    'Assigned: ${booking.acceptedAmbulanceName}',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 13, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd MMM · hh:mm a').format(booking.createdAt),
                  style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
            if (isCancelled) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 12, color: Color(0xFFDC2626)),
                    const SizedBox(width: 4),
                    Text(
                      _getCancelledByText(),
                      style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626)),
                    ),
                  ],
                ),
              ),
            ],
            if (showAccept) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: Icon(Icons.close, size: 18),
                      label: Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondaryOf(context),
                        side: BorderSide(color: AppColors.borderOf(context)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onAccept,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Accept'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (showComplete) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onComplete,
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('Complete Trip'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
            if (showCancel) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancel Trip'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
            if (isCompleted && booking.isRated) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  ...List.generate(5, (i) => Icon(
                    i < booking.rating!
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 16,
                    color: const Color(0xFFF59E0B),
                  )),
                  const SizedBox(width: 6),
                  Text(
                    '${booking.rating}/5',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  if (booking.review != null && booking.review!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '"${booking.review}"',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
