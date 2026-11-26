import 'package:flutter/foundation.dart';

/// Which App Check attestation provider a build may use.
enum AppCheckProviderKind {
  /// Play Integrity (Android) / DeviceCheck (iOS). The only provider allowed in
  /// production.
  platformAttestation,

  /// Firebase App Check debug provider. Debug builds, or explicitly flagged
  /// staging test builds, only.
  debug,
}

/// Compile-time inputs for the provider decision.
///
/// * `APP_ENV`: must be passed explicitly as `staging` for a release build to
///   be allowed the debug provider. A release build without `APP_ENV` is NOT
///   treated as staging here, even though other code defaults to staging.
/// * `APP_CHECK_DEBUG_PROVIDER=true`: explicit opt-in for staging test APKs.
abstract final class AppCheckBuildConfig {
  static const bool hasAppEnv = bool.hasEnvironment('APP_ENV');
  static const String appEnv = String.fromEnvironment('APP_ENV');
  static const bool debugProviderRequested =
      bool.fromEnvironment('APP_CHECK_DEBUG_PROVIDER');
}

/// Decides the App Check provider. Pure and unit tested.
///
/// Rules:
/// 1. `APP_ENV=production` always uses platform attestation, in every build mode.
///    A production build that requests the debug provider is a configuration
///    error and throws, so it can never ship silently.
/// 2. Debug mode (`flutter run`) may use the debug provider.
/// 3. A release/profile build may use the debug provider only when it was built
///    with an explicit `APP_ENV=staging` AND `APP_CHECK_DEBUG_PROVIDER=true`.
/// 4. Everything else uses platform attestation. A debug token dart-define on
///    its own no longer switches a release build to the debug provider.
abstract final class AppCheckProviderPolicy {
  static AppCheckProviderKind resolve({
    required bool isDebugMode,
    required bool hasAppEnv,
    required String appEnv,
    required bool debugProviderRequested,
  }) {
    final env = appEnv.trim().toLowerCase();
    if (env == 'production') {
      if (debugProviderRequested) {
        throw StateError(
          'APP_CHECK_DEBUG_PROVIDER=true is not allowed with APP_ENV=production.',
        );
      }
      return AppCheckProviderKind.platformAttestation;
    }
    if (isDebugMode) return AppCheckProviderKind.debug;
    if (hasAppEnv && env == 'staging' && debugProviderRequested) {
      return AppCheckProviderKind.debug;
    }
    return AppCheckProviderKind.platformAttestation;
  }

  /// Provider for the running build.
  static AppCheckProviderKind current() => resolve(
        isDebugMode: kDebugMode,
        hasAppEnv: AppCheckBuildConfig.hasAppEnv,
        appEnv: AppCheckBuildConfig.appEnv,
        debugProviderRequested: AppCheckBuildConfig.debugProviderRequested,
      );
}
