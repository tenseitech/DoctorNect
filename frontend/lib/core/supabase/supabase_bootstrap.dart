import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bootstrap and lifecycle management for Supabase in DoctorNect.
abstract final class SupabaseBootstrap {
  static bool isReady = false;
  static String? lastInitError;

  static const String _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String appEnv =
      String.fromEnvironment('APP_ENV', defaultValue: 'staging');

  static String? _debugAppEnvOverride;

  @visibleForTesting
  static bool? debugIsReleaseModeOverride;

  static bool get _effectiveReleaseMode =>
      kReleaseMode || (debugIsReleaseModeOverride ?? false);

  @visibleForTesting
  static String? get debugAppEnvOverride => _debugAppEnvOverride;

  @visibleForTesting
  static set debugAppEnvOverride(String? value) {
    if (_effectiveReleaseMode && value != null) {
      throw UnsupportedError('debugAppEnvOverride cannot be set in release mode.');
    }
    _debugAppEnvOverride = value;
  }

  static bool get isProduction {
    if (_effectiveReleaseMode) {
      return appEnv.toLowerCase() == 'production';
    }
    return (_debugAppEnvOverride ?? appEnv).toLowerCase() == 'production';
  }

  /// Test stand-in for the Firebase ID token passed to Supabase.
  @visibleForTesting
  static Future<String?> Function()? debugAccessTokenOverride;

  static Future<String?> currentFirebaseAccessToken({
    bool forceRefresh = false,
  }) async {
    if (debugAccessTokenOverride != null) {
      return debugAccessTokenOverride!();
    }
    if (Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(forceRefresh);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> refreshAndVerifySession({bool forceRefresh = true}) async {
    if (debugAccessTokenOverride != null) {
      return debugAccessTokenOverride!();
    }
    if (Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final tokenResult = await user.getIdTokenResult(forceRefresh);
    final role = tokenResult.claims?['role'];
    if (role != 'authenticated') {
      throw MissingSupabaseClaimException(
        'Firebase ID token for UID "${user.uid}" is missing custom claim role="authenticated". '
        'Ensure backend claims backfill or syncUserClaimsOnProfileWrite has run.',
      );
    }

    final token = tokenResult.token;
    if (token != null && token.isNotEmpty && isReady) {
      try {
        client.realtime.setAuth(token);
      } catch (_) {}
    }
    return token;
  }

  static Future<String?> refreshSession() async {
    return refreshAndVerifySession(forceRefresh: true);
  }

  static bool get hasConfig => _envUrl.isNotEmpty && _envAnonKey.isNotEmpty;

  static const String defaultUrl = 'https://your-project-ref.supabase.co';
  static const String defaultAnonKey = 'your-anon-key';

  static String get resolvedUrl => _envUrl.isNotEmpty ? _envUrl : defaultUrl;
  static String get resolvedAnonKey =>
      _envAnonKey.isNotEmpty ? _envAnonKey : defaultAnonKey;

  static Future<String> resolveRegistrationProfileId({
    required String role,
    required String defaultClientId,
  }) async {
    return defaultClientId;
  }

  static Future<void> ensureSupabaseSignedOutIfFirebaseFlow() async {
    try {
      if (isReady && client.auth.currentSession != null) {
        await client.auth.signOut();
      }
    } catch (_) {}
  }

  static SupabaseClient? _debugClientOverride;

  @visibleForTesting
  static SupabaseClient? get debugClientOverride => _debugClientOverride;

  @visibleForTesting
  static set debugClientOverride(SupabaseClient? value) {
    if (kReleaseMode && value != null) {
      throw UnsupportedError('debugClientOverride cannot be set in release mode.');
    }
    _debugClientOverride = value;
  }

  static SupabaseClient get client {
    if (!kReleaseMode && _debugClientOverride != null) {
      return _debugClientOverride!;
    }
    if (!isReady) {
      throw StateError(
        'Supabase has not been initialized. Call SupabaseBootstrap.initialize() first.',
      );
    }
    return Supabase.instance.client;
  }

  @visibleForTesting
  static void resetForTesting() {
    isReady = false;
    lastInitError = null;
    _debugClientOverride = null;
    debugAccessTokenOverride = null;
    debugAppEnvOverride = null;
    debugIsReleaseModeOverride = null;
  }

  static Future<bool> initialize({String? url, String? anonKey}) async {
    if (isReady) return true;

    final targetUrl = url ?? (hasConfig ? _envUrl : '');
    final targetKey = anonKey ?? (hasConfig ? _envAnonKey : '');

    if (targetUrl.isEmpty || targetKey.isEmpty) {
      isReady = false;
      lastInitError = 'Supabase URL or Anon Key is missing.';
      if (kDebugMode) {
        debugPrint(
          '[SupabaseBootstrap] Skipping initialization: SUPABASE_URL or SUPABASE_ANON_KEY not configured.',
        );
      }
      return false;
    }

    try {
      lastInitError = null;

      await Supabase.initialize(
        url: targetUrl,
        // ignore: deprecated_member_use
        anonKey: targetKey,
        accessToken: currentFirebaseAccessToken,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          autoRefreshToken: true,
        ),
        realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
      );

      isReady = true;

      if (!isProduction) {
        final initialToken = await currentFirebaseAccessToken();
        if (initialToken != null && initialToken.isNotEmpty) {
          try {
            client.realtime.setAuth(initialToken);
          } catch (_) {}
        }

        if (Firebase.apps.isNotEmpty) {
          FirebaseAuth.instance.idTokenChanges().listen((user) async {
            if (user != null && isReady) {
              try {
                final token = await user.getIdToken();
                if (token != null && token.isNotEmpty) {
                  client.realtime.setAuth(token);
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint(
                    '[SupabaseBootstrap] Failed to set realtime auth on token change: $e',
                  );
                }
              }
            }
          });
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[SupabaseBootstrap] Supabase initialized successfully on ${defaultTargetPlatform.name}',
        );
      }
      return true;
    } catch (e, st) {
      isReady = false;
      lastInitError = e.toString();
      if (kDebugMode) {
        debugPrint('[SupabaseBootstrap] Initialization error: $e\n$st');
      }
      return false;
    }
  }
}

class MissingSupabaseClaimException implements Exception {
  const MissingSupabaseClaimException(this.message);

  final String message;

  @override
  String toString() => 'MissingSupabaseClaimException: $message';
}
