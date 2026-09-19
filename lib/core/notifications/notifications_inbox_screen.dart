import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../constants/app_icons.dart';
import '../layout/responsive_layout.dart';
import '../theme/app_colors.dart';
import 'app_notification.dart';
import 'app_notification_navigator.dart';
import 'in_app_notification_service.dart';
import '../../core/theme/app_typography.dart';

enum _InboxFilter { newAlerts, unread }

class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({super.key, required this.audience});

  final NotificationAudience audience;

  @override
  State<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  _InboxFilter _filter = _InboxFilter.newAlerts;

  Color get _accent => widget.audience == NotificationAudience.doctor
      ? AppColors.doctorBlue
      : AppColors.patientTeal;

  bool get _isPatient => widget.audience == NotificationAudience.patient;

  List<AppNotification> get _inbox => _isPatient
      ? InAppNotificationService.instance.patientInbox
      : InAppNotificationService.instance.doctorInbox;

  List<AppNotification> get _items {
    return switch (_filter) {
      _InboxFilter.newAlerts => _inbox.toList(),
      _InboxFilter.unread => _inbox.where((n) => !n.isRead).toList(),
    };
  }

  int get _unreadCount => _inbox.where((n) => !n.isRead).length;

  Future<void> _markRead(String id) async {
    if (_isPatient) {
      await InAppNotificationService.instance.markPatientRead(id);
    } else {
      await InAppNotificationService.instance.markDoctorRead(id);
    }
  }

  Future<void> _onNotificationTap(AppNotification notification) async {
    if (!mounted) return;
    await AppNotificationNavigator.open(
      context,
      notification: notification,
      audience: widget.audience,
    );
    if (!mounted) return;
    await _markRead(notification.id);
  }

  Future<void> _markAllRead() async {
    if (_isPatient) {
      await InAppNotificationService.instance.markAllPatientRead();
    } else {
      await InAppNotificationService.instance.markAllDoctorRead();
    }
    if (!mounted) return;
    setState(() => _filter = _InboxFilter.unread);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InAppNotificationService.instance,
      builder: (context, _) {
        final items = _items;
        final unreadCount = _unreadCount;

        return Scaffold(
          backgroundColor: AppColors.cardBgOf(context),
          appBar: AppBar(
            backgroundColor: AppColors.surfaceOf(context),
            foregroundColor: AppColors.textPrimaryOf(context),
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w700),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _accent.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '$unreadCount unread',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: FontWeight.w700,
                        color: _accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: unreadCount > 0 ? _markAllRead : null,
                  style: TextButton.styleFrom(
                    foregroundColor: _accent,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Text(
                    'Mark all read',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    _FilterPill(
                      label: 'New',
                      selected: _filter == _InboxFilter.newAlerts,
                      accent: _accent,
                      onTap: () =>
                          setState(() => _filter = _InboxFilter.newAlerts),
                    ),
                    const SizedBox(width: 12),
                    _FilterPill(
                      label: 'Unread',
                      selected: _filter == _InboxFilter.unread,
                      accent: _accent,
                      onTap: () =>
                          setState(() => _filter = _InboxFilter.unread),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: items.isEmpty
                    ? _EmptyInbox(
                        accent: _accent,
                        unreadOnly: _filter == _InboxFilter.unread,
                      )
                    : Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: ResponsiveLayout.contentMaxWidth(context),
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final n = items[index];
                              return _NotificationTile(
                                notification: n,
                                accent: _accent,
                                onTap: () => unawaited(_onNotificationTap(n)),
                              );
                            },
                          ),
                        ),
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
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unselectedBg = AppColors.surfaceOf(context);
    final unselectedBorder = AppColors.borderOf(context);
    final unselectedTextColor = AppColors.textSecondaryOf(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent : unselectedBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? accent : unselectedBorder,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.white : unselectedTextColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.accent,
    required this.onTap,
  });

  final AppNotification notification;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final time = DateFormat('dd MMM, hh:mm a').format(n.createdAt);
    final palette = _NotificationPalette.forType(n.type, accent);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: n.isRead
                ? AppColors.surfaceOf(context)
                : accent.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: n.isRead
                  ? AppColors.borderOf(context)
                  : accent.withValues(alpha: 0.28),
              width: n.isRead ? 1.0 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: n.isRead
                    ? AppColors.textPrimaryOf(context).withValues(alpha: 0.03)
                    : accent.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (!n.isRead)
                Positioned(
                  left: 0,
                  top: 12,
                  bottom: 12,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4)),
                    ),
                  ),
                ),
              Padding(
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
                          colors: palette.gradient,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color:
                                palette.gradient.last.withValues(alpha: 0.22),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child:
                          Icon(palette.icon, size: 22, color: AppColors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  n.title,
                                  style: GoogleFonts.inter(
                                    fontWeight: n.isRead
                                        ? FontWeight.w600
                                        : FontWeight.w700,
                                    fontSize: AppTypography.bodyMedium,
                                    height: 1.25,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ),
                              if (!n.isRead) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: accent.withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                            color: accent,
                                            shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'UNREAD',
                                        style: GoogleFonts.inter(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: accent,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            n.body,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              color: AppColors.textSecondaryOf(context),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            time,
                            style: GoogleFonts.inter(
                                fontSize: AppTypography.labelSmall,
                                color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
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

class _NotificationPalette {
  const _NotificationPalette({
    required this.gradient,
    required this.icon,
  });

  final List<Color> gradient;
  final IconData icon;

  static _NotificationPalette forType(AppNotificationType type, Color accent) {
    return switch (type) {
      AppNotificationType.appointment => _NotificationPalette(
          gradient: [accent, accent.withValues(alpha: 0.75)],
          icon: Icons.event_available_outlined,
        ),
      AppNotificationType.booking => _NotificationPalette(
          gradient: [accent, accent.withValues(alpha: 0.75)],
          icon: Icons.calendar_month_outlined,
        ),
      AppNotificationType.cancellation => const _NotificationPalette(
          gradient: [Color(0xFFDC2626), Color(0xFFB91C1C)],
          icon: Icons.event_busy_outlined,
        ),
      AppNotificationType.labReport => const _NotificationPalette(
          gradient: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
          icon: Icons.biotech_outlined,
        ),
      AppNotificationType.prescription => const _NotificationPalette(
          gradient: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          icon: AppIcons.prescription,
        ),
      AppNotificationType.reminder => const _NotificationPalette(
          gradient: [Color(0xFFEA580C), Color(0xFFC2410C)],
          icon: Icons.alarm_outlined,
        ),
      AppNotificationType.review => const _NotificationPalette(
          gradient: [Color(0xFFCA8A04), Color(0xFFA16207)],
          icon: Icons.star_outline,
        ),
      AppNotificationType.payout => const _NotificationPalette(
          gradient: [Color(0xFF059669), Color(0xFF047857)],
          icon: Icons.payments_outlined,
        ),
      AppNotificationType.chat => _NotificationPalette(
          gradient: [accent, accent.withValues(alpha: 0.75)],
          icon: Icons.chat_bubble_outline,
        ),
      AppNotificationType.kyc => const _NotificationPalette(
          gradient: [Color(0xFF0891B2), Color(0xFF0E7490)],
          icon: Icons.verified_user_outlined,
        ),
      AppNotificationType.wellness => const _NotificationPalette(
          gradient: [Color(0xFF16A34A), Color(0xFF15803D)],
          icon: Icons.favorite_outline,
        ),
      AppNotificationType.system => const _NotificationPalette(
          gradient: [Color(0xFF64748B), Color(0xFF475569)],
          icon: Icons.info_outline,
        ),
    };
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({
    required this.accent,
    required this.unreadOnly,
  });

  final Color accent;
  final bool unreadOnly;

  @override
  Widget build(BuildContext context) {
    final title = unreadOnly ? 'No unread notifications' : 'All caught up';
    final subtitle = unreadOnly
        ? 'You have read all your notifications.'
        : 'New notifications will appear here.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.notifications_none_outlined,
                      size: 32, color: accent),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
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
                      height: 1.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
