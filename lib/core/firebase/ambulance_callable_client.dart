import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:firebase_app_check/firebase_app_check.dart';

import '../../firebase_options.dart';
import '../security/app_check_service.dart';
import 'ambulance_auth_helper.dart';

/// Ambulance driver Cloud Function callables.
abstract final class AmbulanceCallableClient {
  static const _region = 'asia-south1';

  static FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(
        app: Firebase.app(),
        region: _region,
      );

  /// Username/password verify — web uses CORS-enabled HTTP with explicit Bearer token.
  static Future<Map<String, dynamic>> verifyDriverLogin(
    Map<String, dynamic> data,
  ) async {
    if (kIsWeb) {
      return _verifyDriverLoginWeb(data);
    }
    return call('verifyAmbulanceDriverLogin', data, requireAuth: false);
  }

  static Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data, {
    bool requireAuth = true,
  }) async {
    if (requireAuth) {
      await _prepareAuth();
    }

    final result =
        await _functions.httpsCallable(name).call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data);
  }

  static Future<Map<String, dynamic>> _verifyDriverLoginWeb(
    Map<String, dynamic> data,
  ) async {
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    final url = Uri.parse(
      'https://$_region-$projectId.cloudfunctions.net/verifyAmbulanceDriverLoginHttp',
    );

    await AppCheckService.ensureForCallable();

    final headers = <String, String>{'Content-Type': 'application/json'};
    try {
      final appCheckToken = await FirebaseAppCheck.instance.getToken();
      if (appCheckToken != null && appCheckToken.isNotEmpty) {
        headers['X-Firebase-AppCheck'] = appCheckToken;
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Ambulance web login App Check token failed: $e\n$st');
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final token = await user.getIdToken(true);
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({'data': data}),
    );

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw FirebaseFunctionsException(
          code: 'internal',
          message: 'Unexpected login response.',
        );
      }
      body = Map<String, dynamic>.from(decoded);
    } catch (e) {
      if (e is FirebaseFunctionsException) rethrow;
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Could not verify login. Please try again.',
      );
    }

    if (body.containsKey('error')) {
      final err = Map<String, dynamic>.from(body['error'] as Map);
      throw FirebaseFunctionsException(
        code: _statusToCode(err['status'] as String?),
        message: err['message'] as String? ?? 'Login failed.',
      );
    }

    final result = body['result'];
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return {'result': result};
  }

  static Future<void> _prepareAuth() async {
    if (FirebaseAuth.instance.currentUser == null) {
      final ok = await AmbulanceAuthHelper.ensureSignedIn();
      if (!ok) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'Anonymous sign-in required.',
        );
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Anonymous sign-in required.',
      );
    }

    if (!await AmbulanceAuthHelper.refreshCallableAuthToken()) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Could not obtain auth token.',
      );
    }

    if (kIsWeb) {
      try {
        await user.reload();
        await user.getIdToken(true);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('Ambulance callable auth reload failed: $e\n$st');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  static String _statusToCode(String? status) {
    return switch ((status ?? '').toUpperCase()) {
      'UNAUTHENTICATED' => 'unauthenticated',
      'PERMISSION_DENIED' => 'permission-denied',
      'INVALID_ARGUMENT' => 'invalid-argument',
      'RESOURCE_EXHAUSTED' => 'resource-exhausted',
      'FAILED_PRECONDITION' => 'failed-precondition',
      'ALREADY_EXISTS' => 'already-exists',
      'NOT_FOUND' => 'not-found',
      _ => 'internal',
    };
  }
}
