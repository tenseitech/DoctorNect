import 'package:medibond/core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_notification.dart';
import 'in_app_notification_service.dart';

/// Real-time Firestore inbox sync for the signed-in doctor.
abstract final class DoctorInAppNotificationSync {
  static StreamSubscription<List<AppNotification>>? _sub;
  static final Set<String> _knownNotificationIds = {};
  static var _seededInitialSnapshot = false;

  static void start(String recipientUid) {
    if (recipientUid.isEmpty) return;
    _sub?.cancel();
    _knownNotificationIds.clear();
    _seededInitialSnapshot = false;

    _sub = FirestoreService.instance.inAppNotification.watchForRecipient(recipientUid).listen(
      (notifications) {
        InAppNotificationService.instance.mergeDoctorFirestoreNotifications(notifications);

        if (!_seededInitialSnapshot) {
          _knownNotificationIds
            ..clear()
            ..addAll(notifications.map((n) => n.id));
          _seededInitialSnapshot = true;
          return;
        }

        for (final notification in notifications) {
          if (_knownNotificationIds.contains(notification.id)) continue;
          _knownNotificationIds.add(notification.id);
          if (notification.isRead) continue;
          InAppNotificationService.instance.onDoctorNotificationArrived?.call(notification);
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('Doctor in-app notification sync error: $e\n$st');
        }
      },
    );
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
    _knownNotificationIds.clear();
    _seededInitialSnapshot = false;
  }
}
