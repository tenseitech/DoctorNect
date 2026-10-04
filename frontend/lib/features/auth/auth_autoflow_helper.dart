import 'package:flutter/material.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/validators/form_validators.dart';

/// Helper for DoctorNect auth auto-flow behaviours:
/// 1. 10th-digit auto-send with double-send guard, programmatic prefill guard,
///    same-number cooldown reuse, and smooth keyboard focus.
/// 2. 6th-digit auto-verify with loading/lock guard, wrong-OTP shake & clear,
///    and network error preservation.
abstract final class AuthAutoFlowHelper {
  /// Strips formatting (+91, 91, spaces, dashes) using existing validator normalisation.
  static String? normalizeMobile(String value) {
    return FormValidators.registrationMobileDigits(value);
  }

  /// Checks if Firebase / network is currently not ready or unavailable.
  static bool isOfflineOrUnavailable() {
    return !FirebaseBootstrap.isReady;
  }

  /// Checks if an error string represents a network or server unavailability error.
  static bool isNetworkOrServerError(String? errorMessage) {
    if (errorMessage == null || errorMessage.isEmpty) return false;
    final lower = errorMessage.toLowerCase();
    return lower.contains('network') ||
        lower.contains('connect') ||
        lower.contains('connection') ||
        lower.contains('unavailable') ||
        lower.contains('offline') ||
        lower.contains('timeout') ||
        lower.contains('server') ||
        lower.contains('socket') ||
        lower.contains('firebase is not available');
  }
}

/// Tracks mobile digit transitions to trigger auto-send ONLY when input goes
/// from < 10 valid digits to 10 valid digits through typing, paste, or autofill.
class MobileAutoSendTracker {
  String _previousDigits = '';
  bool _isProgrammatic = false;

  void initialize(String? initialValue) {
    if (initialValue != null && initialValue.isNotEmpty) {
      final digits = FormValidators.registrationMobileDigits(initialValue) ??
          initialValue.replaceAll(RegExp(r'\D'), '');
      _previousDigits = digits;
    }
  }

  void onReturnedFromOtp(String? currentNumber) {
    if (currentNumber != null && currentNumber.isNotEmpty) {
      final digits = FormValidators.registrationMobileDigits(currentNumber) ??
          currentNumber.replaceAll(RegExp(r'\D'), '');
      _previousDigits = digits;
    }
  }

  /// Sanitizes raw input in the controller if it contains +91 / dashes / spaces.
  /// Returns the clean 10-digit number if valid, or null.
  String? checkAndNormalize(TextEditingController controller) {
    final raw = controller.text;
    final normalized = FormValidators.registrationMobileDigits(raw);
    if (normalized != null && normalized != raw) {
      _isProgrammatic = true;
      controller.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      _isProgrammatic = false;
      return normalized;
    }
    return normalized;
  }

  /// Determines whether auto-send should be triggered for the new text.
  /// Updates internal previous digit tracking.
  bool shouldTriggerAutoSend({
    required String currentRaw,
    required bool isBusy,
  }) {
    if (_isProgrammatic || isBusy) return false;

    final normalized = FormValidators.registrationMobileDigits(currentRaw);
    final currentDigits =
        normalized ?? currentRaw.replaceAll(RegExp(r'\D'), '');
    final prevLength = _previousDigits.length;
    _previousDigits = currentDigits;

    // Trigger ONLY when moving from < 10 digits to 10 valid digits
    if (prevLength < 10 && normalized != null && normalized.length == 10) {
      return true;
    }
    return false;
  }
}
