import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase/firebase_bootstrap.dart';

/// Fetches validation rules from Cloud Functions and runs server-side checks.
abstract final class ServerValidationService {
  static const _rulesCacheKey = 'medibond_validation_rules_v1';
  static const _thresholdsCacheKey = 'medibond_vital_thresholds_v1';
  static const _maxFetchAttempts = 3;
  static const _fetchBackoffBaseMs = 800;
  static const _validateRetryCooldown = Duration(seconds: 30);

  static Map<String, dynamic>? _rules;
  static Map<String, dynamic>? _vitalThresholds;
  static bool _loading = false;
  static DateTime? _lastValidateTriggeredRetry;

  static Map<String, dynamic>? get rules => _rules;
  static Map<String, dynamic>? get vitalThresholds => _vitalThresholds;

  /// Injects validation rules in unit tests (mirrors server `getValidationRules`).
  @visibleForTesting
  static void debugSetRules(Map<String, dynamic>? rules) {
    _rules = rules == null ? null : Map<String, dynamic>.from(rules);
  }

  @visibleForTesting
  static void debugReset() {
    _rules = null;
    _vitalThresholds = null;
    _loading = false;
    _lastValidateTriggeredRetry = null;
  }

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Rate-limited background retry when forms hit validation before rules load.
  static void scheduleRetryIfNeeded() {
    if (_rules != null || _loading) return;

    final now = DateTime.now();
    final lastRetry = _lastValidateTriggeredRetry;
    if (lastRetry != null &&
        now.difference(lastRetry) < _validateRetryCooldown) {
      return;
    }
    _lastValidateTriggeredRetry = now;
    unawaited(loadRules());
  }

  static Future<void> loadRules({bool forceRefresh = false}) async {
    if (_loading) return;
    if (!forceRefresh && _rules != null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!forceRefresh) {
      _hydrateFromCache(prefs);
      if (_rules != null) return;
    }

    if (!FirebaseBootstrap.isReady) return;

    _loading = true;
    try {
      for (var attempt = 0; attempt < _maxFetchAttempts; attempt++) {
        if (_rules != null) break;
        if (attempt > 0) {
          final delayMs = _fetchBackoffBaseMs * (1 << (attempt - 1));
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
        if (!FirebaseBootstrap.isReady) break;
        await _fetchRulesFromServer(prefs);
      }
    } finally {
      _loading = false;
    }
  }

  static void _hydrateFromCache(SharedPreferences prefs) {
    final cachedRules = prefs.getString(_rulesCacheKey);
    final cachedThresholds = prefs.getString(_thresholdsCacheKey);
    if (cachedRules != null) {
      try {
        _rules = Map<String, dynamic>.from(jsonDecode(cachedRules) as Map);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('ServerValidationService: invalid rules cache: $e\n$st');
        }
        _rules = null;
      }
    }
    if (cachedThresholds != null) {
      try {
        _vitalThresholds =
            Map<String, dynamic>.from(jsonDecode(cachedThresholds) as Map);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
              'ServerValidationService: invalid thresholds cache: $e\n$st');
        }
        _vitalThresholds = null;
      }
    }
  }

  static Future<Map<String, dynamic>> _fetchRulesPayload() async {
    if (kIsWeb) {
      try {
        final response =
            await http.get(Uri.base.resolve('/api/validation-rules'));
        final body = response.body.trimLeft();
        if (response.statusCode == 200 && body.startsWith('{')) {
          return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'ServerValidationService: hosting rewrite unavailable, using callable: $e');
        }
      }
    }

    final callable = _functions.httpsCallable('getValidationRules');
    final result = await callable.call<Map<String, dynamic>>({});
    return Map<String, dynamic>.from(result.data);
  }

  static Future<bool> _fetchRulesFromServer(SharedPreferences prefs) async {
    try {
      final data = await _fetchRulesPayload();
      final rules = data['rules'];
      final thresholds = data['vitalThresholds'];
      if (rules is Map) {
        _rules = Map<String, dynamic>.from(rules);
        await prefs.setString(_rulesCacheKey, jsonEncode(_rules));
      }
      if (thresholds is Map) {
        _vitalThresholds = Map<String, dynamic>.from(thresholds);
        await prefs.setString(
            _thresholdsCacheKey, jsonEncode(_vitalThresholds));
      }
      return _rules != null;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ServerValidationService.loadRules fetch failed: $e\n$st');
      }
      return false;
    }
  }

  static Future<String?> validateField({
    required String rule,
    required dynamic value,
    Map<String, dynamic>? params,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;
    try {
      final callable = _functions.httpsCallable('validateField');
      final result = await callable.call<Map<String, dynamic>>({
        'rule': rule,
        'value': value,
        'params': params ?? {},
      });
      final error = result.data['error'];
      return error is String ? error : null;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ServerValidationService.validateField failed: $e\n$st');
      }
      return null;
    }
  }

  static Future<Map<String, String>> validateFields(
    List<Map<String, dynamic>> checks,
  ) async {
    if (!FirebaseBootstrap.isReady) return {};
    try {
      final callable = _functions.httpsCallable('validateFormFields');
      final result =
          await callable.call<Map<String, dynamic>>({'checks': checks});
      final errorsRaw = result.data['errors'];
      if (errorsRaw is! Map) return {};
      return errorsRaw.map(
        (key, value) => MapEntry('$key', value?.toString() ?? ''),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ServerValidationService.validateFields failed: $e\n$st');
      }
      return {};
    }
  }

  static Future<Map<String, dynamic>?> vitalAdvisory({
    required String rule,
    required String? value,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;
    try {
      final callable = _functions.httpsCallable('validateVitalAdvisory');
      final result = await callable.call<Map<String, dynamic>>({
        'rule': rule,
        'value': value,
      });
      final advisory = result.data['advisory'];
      if (advisory is Map) {
        return Map<String, dynamic>.from(advisory);
      }
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'ServerValidationService.vitalAdvisory rate/limit: ${e.code} ${e.message}',
        );
      }
      // Propagate rate-limit as a soft advisory payload so UI can show a toast.
      if (e.code == 'resource-exhausted') {
        return {
          'blocked': true,
          'message': e.message?.trim().isNotEmpty == true
              ? e.message!
              : 'Too many AI advisory requests. Please wait and try again.',
        };
      }
      return null;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ServerValidationService.vitalAdvisory failed: $e\n$st');
      }
      return null;
    }
  }
}
