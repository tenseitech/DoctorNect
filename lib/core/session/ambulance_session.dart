import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class AmbulanceSession {
  static const _keyId = 'ambulance_session_id';
  static const _keyName = 'ambulance_session_name';
  static const _keyDriver = 'ambulance_session_driver';
  static const _keyStartedMs = 'ambulance_session_started_ms';
  static const Duration maxAge = Duration(hours: 12);

  static int _sessionGeneration = 0;

  static String loggedInAmbulanceId = '';
  static String loggedInAmbulanceName = '';
  static String loggedInDriverName = '';
  static DateTime? _startedAt;

  static Future<void> setAmbulance({
    required String id,
    required String serviceName,
    required String driverName,
  }) async {
    final generation = _sessionGeneration;
    loggedInAmbulanceId = id;
    loggedInAmbulanceName = serviceName;
    loggedInDriverName = driverName;
    _startedAt = DateTime.now();
    await _persist(generation);
  }

  /// Clears in-memory + persisted session. Returns false if localStorage removal failed.
  static Future<bool> clear() async {
    _sessionGeneration++;
    loggedInAmbulanceId = '';
    loggedInAmbulanceName = '';
    loggedInDriverName = '';
    _startedAt = null;
    return _clearPersisted();
  }

  static bool get isLoggedIn => loggedInAmbulanceId.isNotEmpty;

  static bool get isExpired {
    final started = _startedAt;
    if (started == null) return false;
    return DateTime.now().difference(started) > maxAge;
  }

  static void _revertInMemorySession() {
    loggedInAmbulanceId = '';
    loggedInAmbulanceName = '';
    loggedInDriverName = '';
    _startedAt = null;
  }

  /// Persist session to SharedPreferences.
  static Future<void> _persist(int generation) async {
    if (generation != _sessionGeneration) {
      _revertInMemorySession();
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _sessionGeneration) {
        _revertInMemorySession();
        return;
      }

      await prefs.setString(_keyId, loggedInAmbulanceId);
      await prefs.setString(_keyName, loggedInAmbulanceName);
      await prefs.setString(_keyDriver, loggedInDriverName);
      await prefs.setInt(
        _keyStartedMs,
        (_startedAt ?? DateTime.now()).millisecondsSinceEpoch,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AmbulanceSession: failed to persist session: $e\n$st');
      }
    }
  }

  /// Remove session from SharedPreferences.
  static Future<bool> _clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyId);
      await prefs.remove(_keyName);
      await prefs.remove(_keyDriver);
      await prefs.remove(_keyStartedMs);

      final remaining = prefs.getString(_keyId) ?? '';
      if (remaining.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            'AmbulanceSession: clear verification failed — '
            '$_keyId still present after remove.',
          );
        }
        return false;
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AmbulanceSession: failed to clear persisted session: $e\n$st');
      }
      return false;
    }
  }

  /// True if a driver session is persisted (without restoring it in memory).
  static Future<bool> hasPersistedSession() async {
    if (isLoggedIn) return !isExpired;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_keyId) ?? '';
      if (id.isEmpty) return false;
      final startedMs = prefs.getInt(_keyStartedMs);
      if (startedMs != null) {
        final started = DateTime.fromMillisecondsSinceEpoch(startedMs);
        if (DateTime.now().difference(started) > maxAge) {
          await clear();
          return false;
        }
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AmbulanceSession: hasPersistedSession read failed: $e\n$st');
      }
      return false;
    }
  }

  /// Try to restore session from SharedPreferences.
  /// Returns true if a session was restored.
  static Future<bool> restoreSession() async {
    if (isLoggedIn) {
      if (isExpired) {
        await clear();
        return false;
      }
      return true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_keyId) ?? '';
      if (id.isEmpty) return false;
      final startedMs = prefs.getInt(_keyStartedMs);
      if (startedMs != null) {
        final started = DateTime.fromMillisecondsSinceEpoch(startedMs);
        if (DateTime.now().difference(started) > maxAge) {
          await clear();
          return false;
        }
        _startedAt = started;
      } else {
        // Legacy sessions without timestamp must re-authenticate.
        await clear();
        return false;
      }
      loggedInAmbulanceId = id;
      loggedInAmbulanceName = prefs.getString(_keyName) ?? '';
      loggedInDriverName = prefs.getString(_keyDriver) ?? '';
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AmbulanceSession: restoreSession failed: $e\n$st');
      }
      return false;
    }
  }
}

