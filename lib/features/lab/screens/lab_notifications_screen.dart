import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/lab_session.dart';
import '../../../core/theme/app_colors.dart';
import '../data/lab_notification_store.dart';
import '../models/lab_notification.dart';
import 'package:medibond/features/shared/widgets/lab_page_layout.dart';
import '../../../core/theme/app_typography.dart';

enum _LabNotifFilter { all, unread, read }

class LabNotificationsScreen extends StatefulWidget {
  const LabNotificationsScreen({super.key});

  @override
  State<LabNotificationsScreen> createState() => _LabNotificationsScreenState();
}

class _LabNotificationsScreenState extends State<LabNotificationsScreen> {
  _LabNotifFilter _filter = _LabNotifFilter.all;

  static const _labPurple = AppColors.labPurple;
  static const _lineColor = Color(0xFFE2E8F0);

  List<LabNotification> _filtered(List<LabNotification> items) {
    return switch (_filter) {
      _LabNotifFilter.all => items,
      _LabNotifFilter.unread => items.where((n) => !n.isRead).toList(),
      _LabNotifFilter.read => items.where((n) => n.isRead).toList(),
    };
  }

  Map<String, List<LabNotification>> _groupByDay(List<LabNotification> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final groups = <String, List<LabNotification>>{};
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
    final labId = LabSession.loggedInLabId;

    return ListenableBuilder(
      listenable: LabNotificationStore.instance,
      builder: (context, _) {
        final allItems = LabNotificationStore.instance.forLab(labId);
        final unreadCount =
            LabNotificationStore.instance.unreadCountForLab(labId);
        final items = _filtered(allItems);
        final groups = _groupByDay(items);

        return LabPageLayout(
          child: Column(
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
                              ? '$unreadCount unread · connection, orders & bookings'
                              : 'Connection updates, new orders, and booking alerts',
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
                        LabNotificationStore.instance.markAllReadForLab(labId);
                        setState(() => _filter = _LabNotifFilter.all);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _labPurple,
                        side: const BorderSide(color: _labPurple),
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
                          selected: _filter == _LabNotifFilter.all,
                          onTap: () =>
                              setState(() => _filter = _LabNotifFilter.all),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _FilterPill(
                          label: 'Unread',
                          count: unreadCount,
                          selected: _filter == _LabNotifFilter.unread,
                          onTap: () =>
                              setState(() => _filter = _LabNotifFilter.unread),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _FilterPill(
                          label: 'Read',
                          count: allItems.length - unreadCount,
                          selected: _filter == _LabNotifFilter.read,
                          onTap: () =>
                              setState(() => _filter = _LabNotifFilter.read),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: items.isEmpty
                    ? _EmptyNotifications(filter: _filter)
                    : ListView(
                        children: [
                          for (final entry in groups.entries) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 10, top: 4),
                              child: Text(
                                entry.key,
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.labelMedium,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondaryOf(context),
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            for (var i = 0; i < entry.value.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              _LabNotificationCard(
                                notification: entry.value[i],
                                onTap: () => LabNotificationStore.instance
                                    .markRead(entry.value[i].id),
                              ),
                            ],
                            const SizedBox(height: 8),
                          ],
                          SizedBox(
                              height:
                                  ResponsiveLayout.isCompact(context) ? 8 : 16),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
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

  static const _labPurple = AppColors.labPurple;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? _labPurple : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? AppColors.surfaceOf(context)
                      : AppColors.textSecondaryOf(context),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.white.withValues(alpha: 0.22)
                        : _labPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? AppColors.surfaceOf(context) : _labPurple,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LabNotificationCard extends StatelessWidget {
  const _LabNotificationCard({
    required this.notification,
    required this.onTap,
  });

  final LabNotification notification;
  final VoidCallback onTap;

  static const _labPurple = AppColors.labPurple;

  @override
  Widget build(BuildContext context) {
    final style = _LabNotificationStyle.forNotification(notification);
    final timeLabel = _formatTime(notification.createdAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: notification.isRead
                  ? const Color(0xFFE2E8F0)
                  : _labPurple.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: style.gradient,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(style.icon, size: 21, color: AppColors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.bodyMedium,
                                fontWeight: notification.isRead
                                    ? FontWeight.w600
                                    : FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (!notification.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 8, top: 4),
                              decoration: const BoxDecoration(
                                color: _labPurple,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.message,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodySmall,
                          color: AppColors.textSecondaryOf(context),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: style.badgeColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              style.badgeLabel,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: style.badgeColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeLabel,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelSmall,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24 && now.day == time.day) {
      return DateFormat('hh:mm a').format(time);
    }
    return DateFormat('dd MMM, hh:mm a').format(time);
  }
}

class _LabNotificationStyle {
  const _LabNotificationStyle({
    required this.gradient,
    required this.icon,
    required this.badgeLabel,
    required this.badgeColor,
  });

  final List<Color> gradient;
  final IconData icon;
  final String badgeLabel;
  final Color badgeColor;

  static _LabNotificationStyle forNotification(LabNotification n) {
    final title = n.title.toLowerCase();
    if (title.contains('booking')) {
      return const _LabNotificationStyle(
        gradient: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
        icon: Icons.calendar_month_outlined,
        badgeLabel: 'Booking',
        badgeColor: Color(0xFF7C3AED),
      );
    }
    if (title.contains('order')) {
      return const _LabNotificationStyle(
        gradient: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
        icon: Icons.science_outlined,
        badgeLabel: 'Order',
        badgeColor: Color(0xFF2563EB),
      );
    }
    if (title.contains('invite') || title.contains('request sent')) {
      return const _LabNotificationStyle(
        gradient: [Color(0xFF0891B2), Color(0xFF0E7490)],
        icon: Icons.person_add_alt_1_outlined,
        badgeLabel: 'Connect',
        badgeColor: Color(0xFF0891B2),
      );
    }
    if (title.contains('approved')) {
      return const _LabNotificationStyle(
        gradient: [Color(0xFF059669), Color(0xFF047857)],
        icon: Icons.check_circle_outline,
        badgeLabel: 'Approved',
        badgeColor: Color(0xFF059669),
      );
    }
    if (title.contains('rejected') || title.contains('declined')) {
      return const _LabNotificationStyle(
        gradient: [Color(0xFFDC2626), Color(0xFFB91C1C)],
        icon: Icons.cancel_outlined,
        badgeLabel: 'Declined',
        badgeColor: Color(0xFFDC2626),
      );
    }
    return const _LabNotificationStyle(
      gradient: [AppColors.labPurple, Color(0xFF6D28D9)],
      icon: Icons.notifications_outlined,
      badgeLabel: 'Alert',
      badgeColor: AppColors.labPurple,
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications({required this.filter});

  final _LabNotifFilter filter;

  static const _labPurple = AppColors.labPurple;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = switch (filter) {
      _LabNotifFilter.unread => (
          'No unread alerts',
          'You\'re all caught up. New bookings and orders will show up here.',
          Icons.mark_email_read_outlined,
        ),
      _LabNotifFilter.read => (
          'No read notifications',
          'Notifications you open will appear in this list.',
          Icons.inbox_outlined,
        ),
      _LabNotifFilter.all => (
          'No notifications yet',
          'Connection updates, lab orders, and patient bookings will appear here.',
          Icons.notifications_none_outlined,
        ),
    };

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _labPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: _labPurple),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                color: AppColors.textSecondaryOf(context),
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
