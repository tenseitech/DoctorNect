/// Public marketing / deep-link URLs (`--dart-define=PUBLIC_WEB_ORIGIN=https://…`).
abstract final class AppWebUrls {
  static const String publicWebOrigin = String.fromEnvironment(
    'PUBLIC_WEB_ORIGIN',
    defaultValue: 'https://doctornect.com',
  );

  static String get websiteUrl => publicWebOrigin;

  static String get appDownloadUrl => '$publicWebOrigin/download';

  static String get inviteJoinUrl => '$publicWebOrigin/join';

  static String get ambulanceSetupUrl => '$publicWebOrigin/ambulance-setup';

  static const supportEmail = 'support@doctornect.com';
}