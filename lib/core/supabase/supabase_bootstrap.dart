import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bootstrap and lifecycle management for Supabase in DoctorNect.
/// Allows parallel execution alongside Firebase during the staged migration window.
abstract final class SupabaseBootstrap {
  static bool isReady = false;
  static String? lastInitError;

  // Compile-time environment variables injected via --dart-define
  static const String _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Fallback configuration placeholders (replace with your project ref if not using dart-define)
  static const String defaultUrl = 'https://your-project-ref.supabase.co';
  static const String defaultAnonKey = 'your-anon-key';

  static String get resolvedUrl => _envUrl.isNotEmpty ? _envUrl : defaultUrl;
  static String get resolvedAnonKey =>
      _envAnonKey.isNotEmpty ? _envAnonKey : defaultAnonKey;

  /// Global accessor to the Supabase client instance
  static SupabaseClient get client {
    if (!isReady) {
      throw StateError(
          'Supabase has not been initialized. Call SupabaseBootstrap.initialize() first.');
    }
    return Supabase.instance.client;
  }

  /// Initializes Supabase client with local persistence and auto refresh
  static Future<bool> initialize({
    String? url,
    String? anonKey,
  }) async {
    if (isReady) return true;

    final targetUrl = url ?? resolvedUrl;
    final targetKey = anonKey ?? resolvedAnonKey;

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
        realtimeClientOptions: const RealtimeClientOptions(
          eventsPerSecond: 10,
        ),
      );

      isReady = true;
      if (kDebugMode) {
        debugPrint(
            '[SupabaseBootstrap] Supabase initialized successfully on ${defaultTargetPlatform.name}');
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
