import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lab_notification.dart';

class LabNotificationStore extends ChangeNotifier {
  LabNotificationStore._();

  static final LabNotificationStore instance = LabNotificationStore._();

  final List<LabNotification> _notifications = [];

  void clear() {
    _notifications.clear();
    notifyListeners();
  }

  String _storageKey(LabNotification n) {
    if (n.referenceId != null && n.referenceId!.isNotEmpty) {
      return 'lab_notif_read_${n.labId}_${n.referenceId}';
    }
    return 'lab_notif_read_${n.labId}_${n.title.hashCode}_${n.message.hashCode}';
  }

  List<LabNotification> forLab(String labId) =>
      _notifications.where((n) => n.labId == labId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int unreadCountForLab(String labId) =>
      forLab(labId).where((n) => !n.isRead).length;

  Future<void> addLab({
    required String labId,
    required String title,
    required String message,
    String? referenceId,
    DateTime? createdAt,
  }) async {
    final notification = LabNotification(
      id: 'lab-n-${DateTime.now().microsecondsSinceEpoch}',
      labId: labId,
      title: title,
      message: message,
      createdAt: createdAt ?? DateTime.now(),
      referenceId: referenceId,
    );

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_storageKey(notification)) == true) {
      notification.isRead = true;
    }

    _notifications.insert(0, notification);
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].id == id && !_notifications[i].isRead) {
        _notifications[i].isRead = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_storageKey(_notifications[i]), true);
        notifyListeners();
        return;
      }
    }
  }

  Future<void> markAllReadForLab(String labId) async {
    var changed = false;
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].labId == labId && !_notifications[i].isRead) {
        _notifications[i].isRead = true;
        await prefs.setBool(_storageKey(_notifications[i]), true);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}
