import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_bootstrap.dart';

enum AuthPath { login, register, blockedWrongRole, unknown }

class AuthResolution {
  final AuthPath path;
  final String? message;

  const AuthResolution({required this.path, this.message});
}

class OtpSendResult {
  final bool success;
  final String? challengeId;
  final bool isDemo;
  final String? error;

  const OtpSendResult({
    required this.success,
    this.challengeId,
    this.isDemo = false,
    this.error,
  });
}

class SupabaseAuthResult {
  final bool success;
  final User? user;
  final Session? session;
  final String? role;
  final bool isNewUser;
  final String? error;

  const SupabaseAuthResult({
    required this.success,
    this.user,
    this.session,
    this.role,
    this.isNewUser = false,
    this.error,
  });
}

/// Service managing phone OTP authentication via the auth-otp Edge Function
/// and establishing native Supabase sessions.
class SupabaseAuthService {
  static final SupabaseAuthService instance = SupabaseAuthService._();
  SupabaseAuthService._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Uri _edgeFunctionUri(String functionName) {
    final baseUrl = SupabaseBootstrap.resolvedUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$baseUrl/functions/v1/$functionName');
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'apikey': SupabaseBootstrap.resolvedAnonKey,
  };

  /// 1. Resolve whether user should login, register, or is blocked due to wrong role
  Future<AuthResolution> resolvePath({
    required String mobile,
    required String role,
  }) async {
    try {
      final res = await http.post(
        _edgeFunctionUri('auth-otp'),
        headers: _headers,
        body: jsonEncode({
          'action': 'resolve-path',
          'mobile': mobile,
          'role': role,
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final pathStr = data['path'] as String?;

      if (pathStr == 'login') return const AuthResolution(path: AuthPath.login);
      if (pathStr == 'register') return const AuthResolution(path: AuthPath.register);
      if (pathStr == 'blocked_wrong_role') {
        return AuthResolution(
          path: AuthPath.blockedWrongRole,
          message: data['message'] as String?,
        );
      }
      return const AuthResolution(path: AuthPath.unknown);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAuthService] resolvePath error: $e');
      return AuthResolution(path: AuthPath.unknown, message: e.toString());
    }
  }

  /// 2. Request OTP via MSG91 SMS dispatch
  Future<OtpSendResult> sendOtp({
    required String mobile,
    required String role,
    String intent = 'login',
  }) async {
    try {
      final res = await http.post(
        _edgeFunctionUri('auth-otp'),
        headers: _headers,
        body: jsonEncode({
          'action': 'send-otp',
          'mobile': mobile,
          'role': role,
          'intent': intent,
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400 || data['error'] != null) {
        return OtpSendResult(
          success: false,
          error: data['error'] as String? ?? 'Failed to send OTP',
        );
      }

      return OtpSendResult(
        success: true,
        challengeId: data['challenge_id'] as String?,
        isDemo: data['is_demo'] == true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAuthService] sendOtp error: $e');
      return OtpSendResult(success: false, error: e.toString());
    }
  }

  /// 3. Verify OTP code and exchange for a full Supabase session
  Future<SupabaseAuthResult> verifyOtp({
    required String mobile,
    required String role,
    required String otp,
    required String challengeId,
  }) async {
    try {
      final res = await http.post(
        _edgeFunctionUri('auth-otp'),
        headers: _headers,
        body: jsonEncode({
          'action': 'verify-otp',
          'mobile': mobile,
          'role': role,
          'otp': otp,
          'sessionId': challengeId,
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400 || data['error'] != null) {
        return SupabaseAuthResult(
          success: false,
          error: data['error'] as String? ?? 'Verification failed',
        );
      }

      final tokenHash = data['token_hash'] as String?;
      if (tokenHash == null) {
        return const SupabaseAuthResult(
          success: false,
          error: 'Missing authentication token from server',
        );
      }

      // Complete authentication by verifying magiclink token in Supabase
      final authResponse = await _client.auth.verifyOTP(
        tokenHash: tokenHash,
        type: OtpType.magiclink,
      );

      return SupabaseAuthResult(
        success: authResponse.session != null,
        user: authResponse.user,
        session: authResponse.session,
        role: data['role'] as String?,
        isNewUser: data['is_new_user'] == true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAuthService] verifyOtp error: $e');
      return SupabaseAuthResult(success: false, error: e.toString());
    }
  }

  /// Sign out from Supabase
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseAuthService] signOut error: $e');
    }
  }
}
