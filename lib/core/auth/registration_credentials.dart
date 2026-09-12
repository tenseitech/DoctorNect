import 'dart:math';

/// Auto-generated credentials for simplified non-patient registration.
abstract final class RegistrationCredentials {
  static String emailForMobile(String mobileDigits) =>
      '$mobileDigits@signup.doctornect.app';

  static String generatePassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#\$';
    final rng = Random.secure();
    return List.generate(24, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static String usernameForMobile(String mobileDigits) => 'amb$mobileDigits';

  static String generatePin() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }
}
