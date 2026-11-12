import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/patient/profile/data/patient_profile_mock.dart';
import '../supabase/repositories/supabase_patient_profile_repository.dart';

/// Keeps in-memory notification prefs aligned with backend while the patient is signed in.
abstract final class PatientNotificationPrefsSync {
  static StreamSubscription<dynamic>? _sub;
  static String? _patientId;

  static void start(String patientId) {
    if (patientId.isEmpty) return;
    if (_patientId == patientId && _sub != null) return;

    stop();
    _patientId = patientId;

    _sub = SupabasePatientProfileRepository.instance
        .watchPatientDocument(patientId)
        .listen(
      (data) {
        if (data == null) return;
        final prefs = data['notification_prefs'] ?? data['notificationPrefs'];
        if (prefs is! Map<String, dynamic>) return;
        PatientProfileMock.applyNotificationPrefsFromFirestore(prefs);
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('Patient notification prefs sync error: $e\n$st');
        }
      },
    );
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
    _patientId = null;
  }
}
