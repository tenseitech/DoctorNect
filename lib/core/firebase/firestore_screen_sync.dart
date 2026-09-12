import 'firestore_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../enums/user_type.dart';
import '../data/shared_appointments_store.dart';
import '../../features/lab/data/lab_connection_store.dart';
import '../../features/lab/data/lab_worklist_store.dart';
import '../../features/lab/models/lab_connection_models.dart';
import '../../features/pharmacy/data/pharmacy_connection_store.dart';
import '../../features/pharmacy/models/pharmacy_models.dart';
import 'firebase_bootstrap.dart';
/// Screen-scoped Firestore listeners. Always call [detach] from dispose().
abstract final class FirestoreScreenSync {
  static StreamSubscription<List<PharmacyConnection>>? _pendingConnectionsSub;
  static StreamSubscription<List<LabConnection>>? _labPendingConnectionsSub;
  static StreamSubscription? _labOrdersSub;
  static StreamSubscription? _labBookingsSub;
  static StreamSubscription<List<DoctorNectAppointmentRecord>>? _doctorAppointmentsSub;
  static String? _doctorAppointmentsDoctorId;

  static void attachPendingConnections({
    required UserType role,
    required String profileId,
  }) {
    detachPendingConnections();
    if (!FirebaseBootstrap.isReady) return;

    final Stream<List<PharmacyConnection>> stream = switch (role) {
      UserType.doctor =>
        FirestoreService.instance.pharmacyFirestore.watchPendingConnectionsForDoctor(profileId),
      UserType.medicalStore =>
        FirestoreService.instance.pharmacyFirestore.watchPendingConnectionsForStore(profileId),
      UserType.patient => const Stream.empty(),
      UserType.lab => const Stream.empty(),
      UserType.ambulance => const Stream.empty(),
      UserType.superAdmin => const Stream.empty(),
    };

    _pendingConnectionsSub = stream.listen(
      PharmacyConnectionStore.instance.mergeFirestoreConnections,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) debugPrint('Pharmacy pending connections sync error: $e\n$st');
      },
    );
  }

  static void attachLabPendingConnections({
    required UserType role,
    required String profileId,
  }) {
    detachLabPendingConnections();
    if (!FirebaseBootstrap.isReady) return;

    final Stream<List<LabConnection>> stream = switch (role) {
      UserType.doctor =>
        FirestoreService.instance.labConnection.watchPendingConnectionsForDoctor(profileId),
      UserType.lab =>
        FirestoreService.instance.labConnection.watchPendingConnectionsForLab(profileId),
      UserType.medicalStore => const Stream.empty(),
      UserType.patient => const Stream.empty(),
      UserType.ambulance => const Stream.empty(),
      UserType.superAdmin => const Stream.empty(),
    };

    _labPendingConnectionsSub = stream.listen(
      LabConnectionStore.instance.mergeFirestoreConnections,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) debugPrint('Lab pending connections sync error: $e\n$st');
      },
    );
  }

  static void attachDoctorAppointments(String doctorId) {
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) {
      return;
    }
    if (_doctorAppointmentsDoctorId == doctorId && _doctorAppointmentsSub != null) {
      return;
    }

    detachDoctorAppointments();

    _doctorAppointmentsDoctorId = doctorId;
    _doctorAppointmentsSub =
        FirestoreService.instance.appointment.watchForDoctor(doctorId).listen(
      (records) {
        SharedAppointmentsStore.instance.mergeFromFirestore(
          records,
          pruneMissing: false,
        );
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('Doctor appointments sync error: $e\n$st');
        }
      },
    );
  }

  static void detachDoctorAppointments() {
    unawaited(_doctorAppointmentsSub?.cancel());
    _doctorAppointmentsSub = null;
    _doctorAppointmentsDoctorId = null;
  }

  static void attachLabWorklist(String labId) {
    detachLabWorklist();
    if (!FirebaseBootstrap.isReady || labId.isEmpty) return;

    // Realtime stream for doctor lab orders addressed to this lab.
    _labOrdersSub = FirestoreService.instance.labOrder.watchForLab(labId).listen(
      LabWorklistStore.instance.mergeOrders,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) debugPrint('Lab orders sync error: $e\n$st');
      },
    );
    // Realtime stream for patient lab bookings addressed to this lab.
    _labBookingsSub = FirestoreService.instance.labBooking.watchForLab(labId).listen(
      LabWorklistStore.instance.mergeBookings,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) debugPrint('Lab bookings sync error: $e\n$st');
      },
    );
  }

  static void detachPendingConnections() {
    unawaited(_pendingConnectionsSub?.cancel());
    _pendingConnectionsSub = null;
  }

  static void detachLabPendingConnections() {
    unawaited(_labPendingConnectionsSub?.cancel());
    _labPendingConnectionsSub = null;
  }

  static void detachLabWorklist() {
    unawaited(_labOrdersSub?.cancel());
    _labOrdersSub = null;
    unawaited(_labBookingsSub?.cancel());
    _labBookingsSub = null;
  }

  static void stopAll() {
    detachPendingConnections();
    detachLabPendingConnections();
    detachLabWorklist();
    detachDoctorAppointments();
  }
}
