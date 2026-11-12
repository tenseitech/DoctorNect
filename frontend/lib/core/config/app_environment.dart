/// Compile-time environment selection (`--dart-define=APP_ENV=staging|production`).
abstract final class AppEnvironment {
  static const String appEnv =
      String.fromEnvironment('APP_ENV', defaultValue: 'staging');

  static bool get isProduction =>
      appEnv.trim().toLowerCase() == 'production';

  static bool get isStaging => !isProduction;
}
