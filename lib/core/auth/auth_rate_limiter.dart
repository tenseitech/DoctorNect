import 'package:shared_preferences/shared_preferences.dart';

/// In-memory + SharedPreferences login attempt limiter (sync API).
///
/// Server-side assertLoginAllowed / recordFailedLogin remain the source of
/// truth; this layer blocks obvious local brute force even if callables fail.
abstract final class AuthRateLimiter {
  static const _window = Duration(minutes: 15);
  static const _maxFailures = 5;

  static final Map<String, _AttemptWindow> _memory = {};

  static String _key(String action, String identifier) =>
      '${action.trim().toLowerCase()}:${identifier.trim().toLowerCase()}';

  /// Returns an error message when the identifier is locked out, else null.
  static String? check(String action, String identifier) {
    final key = _key(action, identifier);
    final now = DateTime.now();
    final window = _memory[key];
    if (window == null) return null;
    if (now.difference(window.startedAt) > _window) {
      _memory.remove(key);
      return null;
    }
    if (window.failures >= _maxFailures) {
      return 'Too many login attempts. Please wait 15 minutes and try again.';
    }
    return null;
  }

  static void recordFailure(String action, String identifier) {
    final key = _key(action, identifier);
    final now = DateTime.now();
    final existing = _memory[key];
    if (existing == null || now.difference(existing.startedAt) > _window) {
      _memory[key] = _AttemptWindow(startedAt: now, failures: 1);
    } else {
      existing.failures += 1;
    }
    // Best-effort persist for process restarts.
    // ignore: discarded_futures
    _persist(key, _memory[key]!);
  }

  static void clear(String action, String identifier) {
    final key = _key(action, identifier);
    _memory.remove(key);
    // ignore: discarded_futures
    _clearPersisted(key);
  }

  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('auth_rl_v2_'));
      final now = DateTime.now();
      for (final prefsKey in keys) {
        final raw = prefs.getString(prefsKey);
        if (raw == null) continue;
        final parts = raw.split('|');
        if (parts.length != 2) continue;
        final startedMs = int.tryParse(parts[0]);
        final failures = int.tryParse(parts[1]);
        if (startedMs == null || failures == null) continue;
        final startedAt = DateTime.fromMillisecondsSinceEpoch(startedMs);
        if (now.difference(startedAt) > _window) {
          await prefs.remove(prefsKey);
          continue;
        }
        final logicalKey = prefsKey.substring('auth_rl_v2_'.length);
        _memory[logicalKey] = _AttemptWindow(
          startedAt: startedAt,
          failures: failures,
        );
      }
    } catch (_) {}
  }

  static Future<void> _persist(String key, _AttemptWindow window) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'auth_rl_v2_$key',
        '${window.startedAt.millisecondsSinceEpoch}|${window.failures}',
      );
    } catch (_) {}
  }

  static Future<void> _clearPersisted(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_rl_v2_$key');
    } catch (_) {}
  }
}

class _AttemptWindow {
  _AttemptWindow({required this.startedAt, required this.failures});
  final DateTime startedAt;
  int failures;
}
