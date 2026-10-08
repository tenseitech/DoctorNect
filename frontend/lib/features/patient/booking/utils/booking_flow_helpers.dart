import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';

/// Booking-flow helpers extracted for unit tests (Issue #16 regressions).
abstract final class BookingFlowHelpers {
  BookingFlowHelpers._();

  @visibleForTesting
  static CollectionReference<Map<String, dynamic>>? debugAppointmentsCollection;

  /// Canonical Male | Female | Other for appointments; rejects unset/invalid values.
  static String? resolvePatientGender(String gender) {
    final normalized = AppConstants.normalizePatientGender(gender);
    if (normalized.isEmpty || !AppConstants.genders.contains(normalized)) {
      return null;
    }
    return normalized;
  }

  /// Firestore auto-id — avoids legacy `APT${timestamp}` collisions (Issue #16).
  static String newAppointmentId() {
    final collection = debugAppointmentsCollection ??
        FirebaseFirestore.instance.collection('appointments');
    return collection.doc().id;
  }

  /// Legacy pattern that caused same-day booking collisions before Issue #16.
  @visibleForTesting
  static bool isLegacyAppointmentId(String id) =>
      RegExp(r'^APT\d+$').hasMatch(id);

  static const placeholderPatientId = 'pat-default';

  /// Returns a real patient id, or null when the session/appointment only has
  /// the legacy placeholder (or is empty).
  static String? resolvePatientId({
    required String sessionPatientId,
    String? appointmentPatientId,
  }) {
    final fromAppointment = appointmentPatientId?.trim() ?? '';
    if (fromAppointment.isNotEmpty &&
        fromAppointment != placeholderPatientId) {
      return fromAppointment;
    }
    final fromSession = sessionPatientId.trim();
    if (fromSession.isNotEmpty && fromSession != placeholderPatientId) {
      return fromSession;
    }
    return null;
  }

  @visibleForTesting
  static void debugReset() {
    debugAppointmentsCollection = null;
  }
}
