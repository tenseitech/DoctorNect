import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../data/shared_appointments_store.dart';
import '../firestore_paths.dart';
import '../firebase_bootstrap.dart';
import '../firestore_query_limits.dart';
import '../firestore_read_helper.dart';
import '../mappers/appointment_firestore_mapper.dart';
import 'patient_profile_repository.dart';

class AppointmentRepository {
  AppointmentRepository._();

  static final AppointmentRepository instance = AppointmentRepository._();

  Future<void> save(DoctorNectAppointmentRecord record,
      {String? patientId}) async {
    if (!FirebaseBootstrap.isReady) return;

    // H3 debug-only write failure simulation. kDebugMode is false in release/profile
    // builds, so this block is unreachable for real users even if the dart-define is set.
    if (kDebugMode && const bool.fromEnvironment('SIMULATE_APPT_WRITE_FAIL')) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Simulated write failure for H3 test',
      );
    }

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.appointments)
          .doc(record.id)
          .set(
            AppointmentFirestoreMapper.toMap(record, patientId: patientId),
            SetOptions(merge: true),
          );

      final resolvedPatientId = patientId ?? record.patientId;
      final doctorId = record.doctorId;
      if (resolvedPatientId != null &&
          resolvedPatientId.isNotEmpty &&
          doctorId.isNotEmpty &&
          PatientProfileRepository.isRegisteredPatientId(resolvedPatientId)) {
        await PatientProfileRepository.instance.ensureDoctorPatientLink(
          patientId: resolvedPatientId,
          doctorId: doctorId,
          source: 'appointment',
        );
        await PatientProfileRepository.instance.grantDoctorCareTeamAccess(
          patientId: resolvedPatientId,
          doctorId: doctorId,
        );
      }
    } on FirebaseException catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            'Appointment save failed (${record.id}): ${e.code} ${e.message}\n$st');
      }
      rethrow;
    }
  }

  Future<List<DoctorNectAppointmentRecord>> fetchForDoctor(
    String doctorId, {
    bool preferCache = false,
  }) async {
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) return const [];

    final snapshot = await FirestoreReadHelper.getQuery(
      query: _doctorAppointmentsQuery(doctorId),
      preferCache: preferCache,
      requireServerIfCacheNonEmpty: true,
    );

    return _recordsFromSnapshot(snapshot);
  }

  /// Real-time appointment stream for the signed-in doctor's queue.
  Stream<List<DoctorNectAppointmentRecord>> watchForDoctor(String doctorId) {
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }

    return _doctorAppointmentsQuery(doctorId)
        .snapshots()
        .map(_recordsFromSnapshot);
  }

  /// Real-time appointment stream for the signed-in patient's bookings.
  Stream<List<DoctorNectAppointmentRecord>> watchForPatient(String patientId) {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection(FirestorePaths.appointments)
        .where('patientId', isEqualTo: patientId)
        .orderBy('dateTime', descending: true)
        .limit(FirestoreQueryLimits.doctorAppointments)
        .snapshots()
        .map(_recordsFromSnapshot);
  }

  Query<Map<String, dynamic>> _doctorAppointmentsQuery(String doctorId) {
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    return FirebaseFirestore.instance
        .collection(FirestorePaths.appointments)
        .where('doctorId', isEqualTo: doctorId)
        .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('dateTime', descending: true)
        .limit(FirestoreQueryLimits.doctorAppointments);
  }

  List<DoctorNectAppointmentRecord> _recordsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final records = snapshot.docs
        .map((doc) => AppointmentFirestoreMapper.fromMap(doc.id, doc.data()))
        .whereType<DoctorNectAppointmentRecord>()
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return records;
  }

  Future<List<DoctorNectAppointmentRecord>> fetchForPatient(
    String patientId, {
    bool preferCache = false,
  }) async {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty) return const [];

    final snapshot = await FirestoreReadHelper.getQuery(
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.appointments)
          .where('patientId', isEqualTo: patientId)
          .limit(FirestoreQueryLimits.connectionsPage * 3),
      preferCache: preferCache,
    );

    final records = snapshot.docs
        .map((doc) => AppointmentFirestoreMapper.fromMap(doc.id, doc.data()))
        .whereType<DoctorNectAppointmentRecord>()
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return records;
  }
}
