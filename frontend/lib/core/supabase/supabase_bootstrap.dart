import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_auth_service.dart';

/// Bootstrap and lifecycle management for Supabase in DoctorNect.
/// Allows parallel execution alongside Firebase during the staged migration window.
abstract final class SupabaseBootstrap {
  static bool isReady = false;
  static String? lastInitError;

  // Compile-time environment variables injected via --dart-define
  static const String _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String appEnv =
      String.fromEnvironment('APP_ENV', defaultValue: 'staging');

  static String? _debugAppEnvOverride;

  @visibleForTesting
  static bool? debugIsReleaseModeOverride;

  static bool get _effectiveReleaseMode => debugIsReleaseModeOverride ?? kReleaseMode;

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

  static const bool useSupabaseAuth =
      bool.fromEnvironment('USE_SUPABASE_AUTH', defaultValue: false);

  /// Test override for USE_SUPABASE_AUTH mode — do not use outside test/
  @visibleForTesting
  static bool? debugUseSupabaseAuthOverride;

  /// Test stand-in for the Firebase ID token passed to Supabase.
  @visibleForTesting
  static Future<String?> Function()? debugAccessTokenOverride;

  /// Firebase ID token for Supabase third-party auth (`accessToken`).
  /// Pass [forceRefresh] = true to force Firebase to mint a fresh token (e.g. after custom claim updates).
  /// Returns null when Firebase has no signed-in user.
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

  /// Explicitly forces a token refresh via `getIdToken(true)` and verifies that
  /// the token carries the mandatory Supabase third-party auth claim `role: "authenticated"`.
  /// Throws [MissingSupabaseClaimException] if missing, preventing silent empty query results.
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

  /// Explicitly refreshes the Firebase ID token and returns the new token,
  /// ensuring Supabase PostgREST and Realtime have access to freshly minted custom claims.
  static Future<String?> refreshSession() async {
    return refreshAndVerifySession(forceRefresh: true);
  }

  static bool get isSupabaseAuthEnabled =>
      debugUseSupabaseAuthOverride ?? useSupabaseAuth;

  /// Whether valid Supabase compile-time configuration was provided via --dart-define.
  static bool get hasConfig => _envUrl.isNotEmpty && _envAnonKey.isNotEmpty;

  /// Fallback configuration placeholders (replace with your project ref if not using dart-define)
  static const String defaultUrl = 'https://your-project-ref.supabase.co';
  static const String defaultAnonKey = 'your-anon-key';

  static String get resolvedUrl => _envUrl.isNotEmpty ? _envUrl : defaultUrl;
  static String get resolvedAnonKey =>
      _envAnonKey.isNotEmpty ? _envAnonKey : defaultAnonKey;

  /// Test overrides for unit testing registration gating — do not use outside test/
  @visibleForTesting
  static bool? debugFirebaseUserActiveOverride;
  @visibleForTesting
  static bool? debugSupabaseUserLoggedInOverride;
  @visibleForTesting
  static bool? debugHasActiveSessionOverride;

  /// Explicit check for whether registration should proceed in Supabase mode:
  /// - USE_SUPABASE_AUTH flag is enabled
  /// - SupabaseBootstrap is ready and an authenticated Supabase user is logged in
  /// - No active Firebase user is logged in (FirebaseAuth.instance.currentUser == null)
  /// - The user's role in public.users matches [targetRole]
  static Future<bool> isSupabaseModeForRole(String targetRole) async {
    if (!isSupabaseAuthEnabled) return false;
    final isFirebaseActive = debugFirebaseUserActiveOverride ??
        (FirebaseAuth.instance.currentUser != null);
    if (isFirebaseActive) return false;

    final isSupabaseUserPresent = debugSupabaseUserLoggedInOverride ??
        (isReady && client.auth.currentUser != null);
    if (!isSupabaseUserPresent) return false;

    final profile =
        await SupabaseAuthService.instance.fetchCurrentUserProfile();
    return profile != null && profile.role == targetRole;
  }

  /// When a Firebase flow starts (login or registration), any stale Supabase session is signed out.
  static Future<void> ensureSupabaseSignedOutIfFirebaseFlow() async {
    try {
      final hasSession = debugHasActiveSessionOverride ??
          (isReady && client.auth.currentSession != null);
      if (hasSession) {
        await SupabaseAuthService.instance.signOut();
      }
    } catch (_) {}
  }

  /// Resolves the registration profileId based on the explicit Supabase auth mode:
  /// - If isSupabaseModeForRole(role) is TRUE -> returns the server profile ID from public.users.
  /// - If FALSE (flag off, role mismatch, or Firebase active) -> returns defaultClientId AND clears stale Supabase session.
  static Future<String> resolveRegistrationProfileId({
    required String role,
    required String defaultClientId,
  }) async {
    if (await isSupabaseModeForRole(role)) {
      final serverProfileId =
          await SupabaseAuthService.instance.fetchCurrentProfileId();
      if (serverProfileId != null && serverProfileId.isNotEmpty) {
        return serverProfileId;
      }
    } else {
      await ensureSupabaseSignedOutIfFirebaseFlow();
    }
    return defaultClientId;
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

  /// Global accessor to the Supabase client instance
  static SupabaseClient get client {
    if (!kReleaseMode && _debugClientOverride != null) return _debugClientOverride!;
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
    debugFirebaseUserActiveOverride = null;
    debugSupabaseUserLoggedInOverride = null;
    debugHasActiveSessionOverride = null;
    debugUseSupabaseAuthOverride = null;
    debugAccessTokenOverride = null;
    debugAppEnvOverride = null;
    debugIsReleaseModeOverride = null;
  }

  /// Initializes Supabase client with local persistence and auto refresh.
  /// If [url] and [anonKey] are not provided and compile-time defines
  /// (SUPABASE_URL, SUPABASE_ANON_KEY) are absent, this method is a safe no-op
  /// returning false without throwing or attempting network connections.
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

      // In production, Realtime WebSocket is disabled; queries use adaptive polling via streamTable.
      // In staging, ensure Realtime WebSocket connection is authenticated with initial token.
      if (!isProduction) {
        final initialToken = await currentFirebaseAccessToken();
        if (initialToken != null && initialToken.isNotEmpty) {
          try {
            client.realtime.setAuth(initialToken);
          } catch (_) {}
        }

        // Automatically sync Realtime auth state on re-login or ID token refresh
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

/// Thrown when a Firebase ID token lacks the required Supabase third-party custom claim (`role: "authenticated"`).
class MissingSupabaseClaimException implements Exception {
  const MissingSupabaseClaimException(this.message);

  final String message;

  @override
  String toString() => 'MissingSupabaseClaimException: $message';
}

