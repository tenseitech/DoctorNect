import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';
import '../firebase/firestore_paths.dart';
import '../../features/patient/profile/data/patient_profile_mock.dart';

/// Keeps in-memory notification prefs aligned with Firestore while the patient is signed in.
abstract final class PatientNotificationPrefsSync {
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static String? _patientId;

  static void start(String patientId) {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty) return;
    if (_patientId == patientId && _sub != null) return;

    stop();
    _patientId = patientId;

    _sub = FirebaseFirestore.instance
        .collection(FirestorePaths.patients)
        .doc(patientId)
        .snapshots()
        .listen(
      (snapshot) {
        if (!snapshot.exists) return;
        final prefs = snapshot.data()?['notificationPrefs'];
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
