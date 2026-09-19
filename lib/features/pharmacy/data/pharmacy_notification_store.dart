import 'package:flutter/foundation.dart';

import '../models/pharmacy_models.dart';

class PharmacyNotificationStore extends ChangeNotifier {
  PharmacyNotificationStore._();

  static final PharmacyNotificationStore instance =
      PharmacyNotificationStore._();

  final List<PharmacyNotification> _storeNotifications = [];

  void clear() {
    _storeNotifications.clear();
    notifyListeners();
  }

  List<PharmacyNotification> forStore(String storeId) =>
      _storeNotifications.where((n) => n.userId == storeId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int unreadCountForStore(String storeId) =>
      forStore(storeId).where((n) => !n.isRead).length;

  void addStore({
    required String storeId,
    required String title,
    required String message,
    String? referenceId,
  }) {
    _storeNotifications.insert(
      0,
      PharmacyNotification(
        id: 'pharm-n-${DateTime.now().microsecondsSinceEpoch}',
        userId: storeId,
        userRole: 'medical_store',
        title: title,
        message: message,
        createdAt: DateTime.now(),
        referenceId: referenceId,
      ),
    );
    notifyListeners();
  }

  void markRead(String id) {
    for (var i = 0; i < _storeNotifications.length; i++) {
      if (_storeNotifications[i].id == id && !_storeNotifications[i].isRead) {
        _storeNotifications[i].isRead = true;
        notifyListeners();
        return;
      }
    }
  }

  void markAllReadForStore(String storeId) {
    var changed = false;
    for (var i = 0; i < _storeNotifications.length; i++) {
      if (_storeNotifications[i].userId == storeId &&
          !_storeNotifications[i].isRead) {
        _storeNotifications[i].isRead = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}
