import 'package:medibond/core/firebase/firestore_service.dart';
import 'dart:async';

import '../../features/patient/records/data/patient_lab_booking_store.dart';

/// Keeps the signed-in patient's lab booking store in sync with Firestore.
abstract final class PatientLabBookingWatcher {
  static StreamSubscription<List<LabBookingRecord>>? _sub;

  static void start(String patientId) {
    if (patientId.isEmpty) return;
    _sub?.cancel();

    _sub = FirestoreService.instance.labBooking.watchForPatient(patientId).listen(
      (bookings) {
        PatientLabBookingStore.instance.mergeFromFirestore(bookings);
      },
      onError: (_) {},
    );
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
