import 'package:shared_preferences/shared_preferences.dart';

import 'app_notification.dart';

/// Persists which in-app notifications the user has already read.
abstract final class NotificationReadStore {
  NotificationReadStore._();

  static String _prefsKey(NotificationAudience audience, String userId) {
    final role = audience == NotificationAudience.doctor ? 'doctor' : 'patient';
    return 'notif_read_${role}_$userId';
  }

  static Future<Set<String>> load({
    required NotificationAudience audience,
    required String userId,
  }) async {
    if (userId.isEmpty) return {};
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefsKey(audience, userId)) ??
            const <String>[])
        .toSet();
  }

  static Future<void> markRead({
    required NotificationAudience audience,
    required String userId,
    required String key,
  }) async {
    if (userId.isEmpty || key.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final prefsKey = _prefsKey(audience, userId);
    final current = (prefs.getStringList(prefsKey) ?? const <String>[]).toSet();
    if (current.contains(key)) return;
    current.add(key);
    await prefs.setStringList(prefsKey, current.toList());
  }

  static Future<void> markAllRead({
    required NotificationAudience audience,
    required String userId,
    required Iterable<String> keys,
  }) async {
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final prefsKey = _prefsKey(audience, userId);
    final current = (prefs.getStringList(prefsKey) ?? const <String>[]).toSet();
    var changed = false;
    for (final key in keys) {
      if (key.isEmpty) continue;
      if (current.add(key)) changed = true;
    }
    if (changed) {
      await prefs.setStringList(prefsKey, current.toList());
    }
  }
}
