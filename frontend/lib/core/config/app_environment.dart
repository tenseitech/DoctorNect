/// Compile-time environment selection (`--dart-define=APP_ENV=staging|production`).
abstract final class AppEnvironment {
  static const String appEnv =
      String.fromEnvironment('APP_ENV', defaultValue: 'staging');

  static bool get isProduction =>
      appEnv.trim().toLowerCase() == 'production';

  static bool get isStaging => !isProduction;

  /// AWS S3 vault bucket name (never Firebase Storage for PHI).
  static String get s3VaultBucket {
    const fromDefine = String.fromEnvironment('AWS_S3_VAULT_BUCKET');
    if (fromDefine.isNotEmpty) return fromDefine;
    return isProduction
        ? 'doctornect-prod-vault'
        : 'doctornect-staging-vault';
  }
}
