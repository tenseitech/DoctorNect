import 'package:firebase_auth/firebase_auth.dart';
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
  static const bool useSupabaseAuth =
      bool.fromEnvironment('USE_SUPABASE_AUTH', defaultValue: false);

  /// Test override for USE_SUPABASE_AUTH mode — do not use outside test/
  @visibleForTesting
  static bool? debugUseSupabaseAuthOverride;

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

  /// Global accessor to the Supabase client instance
  static SupabaseClient get client {
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
    debugFirebaseUserActiveOverride = null;
    debugSupabaseUserLoggedInOverride = null;
    debugHasActiveSessionOverride = null;
    debugUseSupabaseAuthOverride = null;
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
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          autoRefreshToken: true,
        ),
        realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
      );

      isReady = true;
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
