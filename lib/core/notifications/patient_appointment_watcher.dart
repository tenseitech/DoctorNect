import 'package:medibond/core/firebase/firestore_service.dart';
import 'dart:async';

import '../data/shared_appointments_store.dart';
/// Keeps the signed-in patient's appointment store in sync with Firestore.
/// Accept/decline alerts are delivered by Cloud Functions (in-app + FCM).
abstract final class PatientAppointmentWatcher {
  static StreamSubscription<List<DoctorNectAppointmentRecord>>? _sub;

  static void start(String patientId) {
    if (patientId.isEmpty) return;
    _sub?.cancel();

    _sub = FirestoreService.instance.appointment.watchForPatient(patientId).listen(
      (records) {
        SharedAppointmentsStore.instance.mergeFromFirestore(records, pruneMissing: false);
      },
      onError: (_) {},
    );
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
