import 'package:shared_preferences/shared_preferences.dart';
import '../enums/user_type.dart';

/// Caches last login email per role for locked login fields.
abstract final class LastLoginStore {
  static final Map<UserType, String> _memory = {};

  static String _key(UserType role) => 'last_login_identifier_${role.name}';

  /// Sync read for first paint
  static String? readCached(UserType role) {
    return _memory[role];
  }

  static Future<String?> load(UserType role) async {
    if (_memory.containsKey(role)) return _memory[role];
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key(role));
      if (saved != null && saved.isNotEmpty) {
        _memory[role] = saved;
        return saved;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> save(UserType role, String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return;
    _memory[role] = trimmed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(role), trimmed);
    } catch (_) {}
  }

  static Future<void> clear(UserType role) async {
    _memory.remove(role);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(role));
    } catch (_) {}
  }
}
