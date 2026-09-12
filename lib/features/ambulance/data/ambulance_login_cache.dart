import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ambulance_models.dart';

/// Persists the last-known ambulance profile for fast login UI (web + mobile).
abstract final class AmbulanceLoginCache {
  static const _profileKey = 'ambulance_login_cached_profile';

  static Future<void> save(RegisteredAmbulance ambulance) async {
    if (ambulance.id.isEmpty || ambulance.username.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _profileKey,
        jsonEncode({
          'id': ambulance.id,
          'data': ambulance.toMap(includePrivateFields: false),
        }),
      );
    } catch (_) {}
  }

  static Future<RegisteredAmbulance?> loadForUsername(String username) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profileKey);
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final id = decoded['id'] as String? ?? '';
      final data = decoded['data'];
      if (id.isEmpty || data is! Map) return null;

      final ambulance = RegisteredAmbulance.fromMap(
        id,
        Map<String, dynamic>.from(data),
      );
      if (ambulance.username.trim().toLowerCase() != normalized) return null;
      return ambulance;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileKey);
    } catch (_) {}
  }
}
