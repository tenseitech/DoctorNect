import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:medibond/core/firebase/repositories/in_app_notification_repository.dart';

import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'app_notification.dart';
import 'in_app_notification_service.dart';

/// In-app inbox sync for the signed-in doctor (Supabase in production).
abstract final class DoctorInAppNotificationSync {
  static StreamSubscription<List<AppNotification>>? _sub;
  static final Set<String> _knownNotificationIds = {};
  static var _seededInitialSnapshot = false;

  static void start(String recipientUid) {
    if (recipientUid.isEmpty) return;
    _sub?.cancel();
    _knownNotificationIds.clear();
    _seededInitialSnapshot = false;

    if (!SupabaseBootstrap.isReady) {
      if (kDebugMode) {
        debugPrint('DoctorInAppNotificationSync: Supabase not ready; skip.');
      }
      return;
    }

    _sub = InAppNotificationRepository.instance
        .watchForRecipient(recipientUid)
        .listen(
      (notifications) {
        InAppNotificationService.instance.mergeDoctorRemoteNotifications(
          notifications,
        );

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
          InAppNotificationService.instance.onDoctorNotificationArrived
              ?.call(notification);
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
