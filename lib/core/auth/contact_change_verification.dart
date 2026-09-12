import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../validators/form_validators.dart';
import '../../widgets/contact_change_otp_dialog.dart';
import 'contact_change_otp_service.dart';

/// Shared OTP gate before saving a new mobile or email on profile edit.
abstract final class ContactChangeVerification {
  static String canonicalMobile(String dialCode, String localDigits) {
    return FormValidators.formatFullPhone(dialCode, localDigits.trim());
  }

  static String canonicalMobileFromStored(String stored) {
    final parsed = FormValidators.parsePhone(stored);
    return canonicalMobile(parsed.dialCode, parsed.localNumber);
  }

  static String canonicalEmail(String value) => value.trim().toLowerCase();

  static bool mobilesEqual(String a, String b) =>
      canonicalMobileFromStored(a) == canonicalMobileFromStored(b);

  static bool emailsEqual(String a, String b) =>
      canonicalEmail(a) == canonicalEmail(b);

  static Future<bool> verifyIfNeeded({
    required BuildContext context,
    required ContactVerificationChannel channel,
    required String destination,
    required String purpose,
    required String? verifiedCanonical,
    Color accentColor = AppColors.patientTeal,
  }) async {
    if (channel == ContactVerificationChannel.email) return false;
    final canonical = canonicalMobileFromStored(destination);
    if (verifiedCanonical == canonical) return true;

    final verified = await ContactChangeOtpDialog.show(
      context,
      channel: channel,
      destination: destination,
      purpose: purpose,
      accentColor: accentColor,
    );
    return verified == true;
  }
}
