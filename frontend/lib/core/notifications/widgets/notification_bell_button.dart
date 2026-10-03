import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../app_notification.dart';
import '../in_app_notification_service.dart';
import '../notifications_inbox_screen.dart';

class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({
    super.key,
    required this.audience,
    this.accentColor,
  });

  final NotificationAudience audience;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InAppNotificationService.instance,
      builder: (context, _) {
        final unread = audience == NotificationAudience.doctor
            ? InAppNotificationService.instance.unreadDoctorCount
            : InAppNotificationService.instance.unreadPatientCount;

        return IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotificationsInboxScreen(audience: audience),
              ),
            );
          },
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 9 ? '9+' : '$unread'),
            backgroundColor: Color(0xFFDC2626),
            child: Icon(Icons.notifications_outlined),
          ),
          color: AppColors.textPrimaryOf(context),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.cardBgOf(context),
            side: BorderSide(color: AppColors.borderOf(context)),
          ),
        );
      },
    );
  }
}
