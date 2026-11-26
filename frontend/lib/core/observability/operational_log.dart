import 'package:flutter/foundation.dart';

/// Privacy-safe operational logging for Flutter (OPS-01 / OPS-02).
/// Never logs PHI, tokens, or full request payloads in release builds.
abstract final class OperationalLog {
  static void info(String event, {Map<String, Object?>? fields}) {
    if (!kDebugMode) return;
    final payload = <String, Object?>{
      'event': event,
      'severity': 'INFO',
      ...?_sanitize(fields),
    };
    debugPrint('[Ops] $payload');
  }

  static void error(
    String event, {
    Object? error,
    Map<String, Object?>? fields,
  }) {
    final message = error?.toString() ?? 'unknown';
    final safeMessage = _redactInline(message);
    final payload = <String, Object?>{
      'event': event,
      'severity': 'ERROR',
      'error': safeMessage.length > 200 ? '${safeMessage.substring(0, 200)}…' : safeMessage,
      ...?_sanitize(fields),
    };
    if (kDebugMode) {
      debugPrint('[Ops] $payload');
    }
  }

  static Map<String, Object?>? _sanitize(Map<String, Object?>? fields) {
    if (fields == null || fields.isEmpty) return null;
    final out = <String, Object?>{};
    for (final e in fields.entries) {
      final key = e.key.toLowerCase();
      if (_sensitiveKeys.contains(key)) {
        out[e.key] = '[REDACTED]';
      } else if (e.value is String) {
        out[e.key] = _redactInline(e.value as String);
      } else {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  static const _sensitiveKeys = {
    'password',
    'otp',
    'token',
    'authorization',
    'prescription',
    'diagnosis',
    'patient_name',
    'phone',
    'email',
  };

  static String _redactInline(String s) {
    if (s.contains('Bearer ')) {
      return s.replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer [REDACTED]');
    }
    if (RegExp(r'^eyJ[\w-]+\.[\w-]+\.[\w-]+$').hasMatch(s)) return '[REDACTED]';
    return s;
  }
}