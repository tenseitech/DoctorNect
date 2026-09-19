import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/session/ambulance_session.dart';
import '../../../core/theme/app_colors.dart';
import '../data/ambulance_store.dart';
import '../models/ambulance_models.dart';
import '../widgets/ambulance_page_layout.dart';
import '../../../core/theme/app_typography.dart';

enum _AlertFilter { all, unread, read }

class AmbulanceNotificationsScreen extends StatefulWidget {
  const AmbulanceNotificationsScreen({
    super.key,
    this.onOpenRequests,
  });

  final VoidCallback? onOpenRequests;

  @override
  State<AmbulanceNotificationsScreen> createState() =>
      _AmbulanceNotificationsScreenState();
}

class _AmbulanceNotificationsScreenState
    extends State<AmbulanceNotificationsScreen> {
  _AlertFilter _filter = _AlertFilter.all;

  static const _accent = Color(0xFFDC2626);
  static const _lineColor = Color(0xFFE2E8F0);

  List<AmbulanceDriverAlert> _filtered(List<AmbulanceDriverAlert> items) {
    return switch (_filter) {
      _AlertFilter.all => items,
      _AlertFilter.unread => items.where((a) => !a.isRead).toList(),
      _AlertFilter.read => items.where((a) => a.isRead).toList(),
    };
  }

  Map<String, List<AmbulanceDriverAlert>> _groupByDay(
      List<AmbulanceDriverAlert> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final groups = <String, List<AmbulanceDriverAlert>>{};
    for (final item in items) {
      final day = DateTime(
          item.createdAt.year, item.createdAt.month, item.createdAt.day);
      final label = day == today
          ? 'Today'
          : day == yesterday
              ? 'Yesterday'
              : DateFormat('dd MMM yyyy').format(item.createdAt);
      groups.putIfAbsent(label, () => []).add(item);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final ambulanceId = AmbulanceSession.loggedInAmbulanceId;

    return AmbulancePageLayout(
      child: Builder(
        builder: (context) {
          final allItems = AmbulanceStore.instance.alertsFor(ambulanceId);
          final unreadCount =
              AmbulanceStore.instance.unreadAlertCount(ambulanceId);
          final items = _filtered(allItems);
          final groups = _groupByDay(items);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications',
                          style: GoogleFonts.inter(
                              fontSize: AppTypography.headlineLarge,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          unreadCount > 0
                              ? '$unreadCount unread · new requests & trip updates'
                              : 'New requests, acceptances, and trip alerts',
                          style: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              color: AppColors.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),
                  if (unreadCount > 0)
                    OutlinedButton(
                      onPressed: () {
                        AmbulanceStore.instance.markAlertsRead(ambulanceId);
                        setState(() => _filter = _AlertFilter.all);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        side: const BorderSide(color: _accent),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                      child: Text(
                        'Mark all read',
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _lineColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Row(
                    children: [
                      Expanded(
                        child: _FilterPill(
                          label: 'All',
                          count: allItems.length,
                          selected: _filter == _AlertFilter.all,
                          onTap: () =>
                              setState(() => _filter = _AlertFilter.all),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _FilterPill(
                          label: 'Unread',
                          count: unreadCount,
                          selected: _filter == _AlertFilter.unread,
                          onTap: () =>
                              setState(() => _filter = _AlertFilter.unread),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _FilterPill(
                          label: 'Read',
                          count: allItems.length - unreadCount,
                          selected: _filter == _AlertFilter.read,
                          onTap: () =>
                              setState(() => _filter = _AlertFilter.read),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          allItems.isEmpty
                              ? 'No notifications yet. New trip requests will appear here.'
                              : 'No ${_filter.name} notifications.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            color: AppColors.textSecondaryOf(context),
                            height: 1.4,
                          ),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final entry in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8, top: 4),
                              child: Text(
                                entry.key,
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.labelMedium,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ),
                            for (final alert in entry.value)
                              _AlertCard(
                                alert: alert,
                                onTap: () {
                                  if (!alert.isRead) {
                                    AmbulanceStore.instance
                                        .markAlertRead(ambulanceId, alert.id);
                                  }
                                  if (alert.bookingId != null) {
                                    widget.onOpenRequests?.call();
                                  }
                                },
                              ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFDC2626).withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyLarge,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? const Color(0xFFDC2626)
                      : AppColors.textPrimaryOf(context),
                ),
              ),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? const Color(0xFFDC2626)
                      : AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onTap});

  final AmbulanceDriverAlert alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: alert.isRead
            ? AppColors.surfaceOf(context)
            : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              alert.isRead ? const Color(0xFFE2E8F0) : const Color(0xFFFDBA74),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.notifications_active_outlined,
                      color: Color(0xFFDC2626), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.title,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyMedium,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        alert.body,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            color: AppColors.textSecondaryOf(context),
                            height: 1.35),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('hh:mm a').format(alert.createdAt),
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall,
                            color: AppColors.textSecondaryOf(context)),
                      ),
                    ],
                  ),
                ),
                if (!alert.isRead)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
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
