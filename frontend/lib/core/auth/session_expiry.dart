import 'package:shared_preferences/shared_preferences.dart';

/// Tracks local app-session lifetime so idle/long-lived sessions must re-auth.
abstract final class SessionExpiry {
  static const Duration maxAge = Duration(days: 7);
  static const _prefsKey = 'auth_session_started_ms';

  static DateTime? _startedAt;

  static DateTime? get startedAt => _startedAt;

  static bool get isExpired {
    final started = _startedAt;
    if (started == null) return false;
    return DateTime.now().difference(started) > maxAge;
  }

  static Future<void> markAuthenticated() async {
    _startedAt = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, _startedAt!.millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_prefsKey);
      if (ms == null || ms <= 0) {
        _startedAt = null;
        return;
      }
      _startedAt = DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      _startedAt = null;
    }
  }

  static Future<void> clear() async {
    _startedAt = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
