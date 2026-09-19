import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../app_notification.dart';
import '../app_notification_navigator.dart';
import '../in_app_notification_service.dart';
import '../../../core/theme/app_typography.dart';

/// Top banner when a new in-app alert arrives (replaces push notification tray).
class InAppNotificationBanner {
  static OverlayEntry? _entry;

  static void show(
    BuildContext context,
    AppNotification notification, {
    required Color accent,
    required NotificationAudience audience,
  }) {
    hide();
    _entry = OverlayEntry(
      builder: (ctx) => _Banner(
        notification: notification,
        accent: accent,
        onDismiss: hide,
        onTap: () {
          hide();
          unawaited(_handleTap(context, notification, audience));
        },
      ),
    );
    Overlay.of(context).insert(_entry!);
    Future.delayed(const Duration(seconds: 5), hide);
  }

  static Future<void> _handleTap(
    BuildContext context,
    AppNotification notification,
    NotificationAudience audience,
  ) async {
    if (!context.mounted) return;
    await AppNotificationNavigator.open(
      context,
      notification: notification,
      audience: audience,
    );
    if (!context.mounted) return;
    if (audience == NotificationAudience.patient) {
      await InAppNotificationService.instance.markPatientRead(notification.id);
    } else {
      await InAppNotificationService.instance.markDoctorRead(notification.id);
    }
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.notification,
    required this.accent,
    required this.onDismiss,
    required this.onTap,
  });

  final AppNotification notification;
  final Color accent;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: top + 8,
      left: 12,
      right: 12,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surfaceOf(context),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: accent.withValues(alpha: 0.4), width: 2),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notifications_active, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: AppTypography.bodyMedium),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'In-app alert · Tap to open',
                        style: GoogleFonts.inter(fontSize: 10, color: accent),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
