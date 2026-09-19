import 'firestore_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/profile_completion_service.dart';
import '../enums/user_type.dart';
import '../../core/data/shared_appointments_store.dart';
import '../../features/doctor/clinical/data/clinical_prescription_store.dart';
import '../../features/doctor/clinical/data/lab_order_store.dart';
import '../../features/doctor/profile/data/doctor_profile_store.dart';
import '../../features/doctor/profile/data/medical_directory_store.dart';
import '../../features/patient/data/registered_doctors_store.dart';
import '../../features/patient/profile/data/patient_profile_mock.dart';
import '../../features/patient/records/data/health_records_mock.dart';
import '../../features/patient/records/data/patient_lab_booking_store.dart';
import '../../features/lab/data/lab_connection_store.dart';
import '../../features/lab/data/lab_registry.dart';
import '../../features/lab/data/lab_worklist_store.dart';
import '../../features/pharmacy/data/medical_store_registry.dart';
import '../../features/pharmacy/data/pharmacy_connection_store.dart';
import '../../features/pharmacy/data/pharmacy_prescription_store.dart';
import 'firebase_bootstrap.dart';

abstract final class FirestoreDataPrefetch {
  static Future<void> prefetch({
    required UserType role,
    required String profileId,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    if (!role.isPatient && !ProfileCompletionService.instance.isComplete) {
      return;
    }

    if (role != UserType.doctor) {
      unawaited(RegisteredDoctorsStore.instance.refreshFromFirestore());
      unawaited(MedicalStoreRegistry.refreshFromFirestore());
      unawaited(LabRegistry.refreshFromFirestore());
    }

    switch (role) {
      case UserType.doctor:
        await Future.wait([
          ClinicalPrescriptionStore.instance
              .refreshForDoctor(preferCache: true)
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Doctor prescription prefetch failed: $e\n$st');
          }),
          FirestoreService.instance.pharmacyFirestore
              .fetchActiveConnectionsForDoctor(profileId, preferCache: true)
              .then((r) => PharmacyConnectionStore.instance
                  .mergeFirestoreConnections(r.items))
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Doctor pharmacy prefetch failed: $e\n$st');
          }),
          FirestoreService.instance.labConnection
              .fetchActiveConnectionsForDoctor(profileId, preferCache: true)
              .then((r) => LabConnectionStore.instance
                  .mergeFirestoreConnections(r.items))
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Doctor lab connections prefetch failed: $e\n$st');
          }),
          SharedAppointmentsStore.instance
              .refreshForDoctor(profileId, preferCache: true)
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Doctor appointments prefetch failed: $e\n$st');
          }),
          DoctorProfileStore.instance
              .loadFromFirestore(profileId)
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Doctor profile prefetch failed: $e\n$st');
          }),
          LabOrderStore.instance
              .refreshForDoctor(preferCache: true)
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Doctor lab orders prefetch failed: $e\n$st');
          }),
          PharmacyPrescriptionStore.instance
              .refreshForDoctor(profileId, preferCache: true)
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Doctor pharmacy deliveries prefetch failed: $e\n$st');
          }),
          MedicalDirectoryStore.instance
              .refreshForDoctor(preferCache: true)
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Doctor medical directory prefetch failed: $e\n$st');
          }),
        ]);
      case UserType.patient:
        await Future.wait([
          FirestoreService.instance.prescription
              .fetchForPatient(profileId, preferCache: false)
              .then((r) => ClinicalPrescriptionStore.instance
                  .mergeFirestoreRecords(r.items))
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Patient prescription prefetch failed: $e\n$st');
          }),
          PatientProfileMock.loadFromFirestore(profileId).catchError((e, st) {
            if (kDebugMode)
              debugPrint('Patient profile prefetch failed: $e\n$st');
          }),
          FirestoreService.instance.appointment
              .fetchForPatient(profileId, preferCache: false)
              .then(
                  (r) => SharedAppointmentsStore.instance.mergeFromFirestore(r))
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Patient appointments prefetch failed: $e\n$st');
          }),
          FirestoreService.instance.patientProfile
              .fetchHealthRecords(profileId)
              .then((r) => HealthRecordsMock.applyFromFirestore(r))
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Patient health records prefetch failed: $e\n$st');
          }),
          PharmacyPrescriptionStore.instance
              .refreshForPatient(profileId, preferCache: false)
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint(
                  'Patient pharmacy deliveries prefetch failed: $e\n$st');
          }),
          LabOrderStore.instance
              .refreshForPatient(profileId, preferCache: false)
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Patient lab orders prefetch failed: $e\n$st');
          }),
          PatientLabBookingStore.instance
              .refreshForPatient(profileId, preferCache: false)
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint(
                  'Patient blood test bookings prefetch failed: $e\n$st');
          }),
        ]);
      case UserType.medicalStore:
        await Future.wait([
          FirestoreService.instance.pharmacyFirestore
              .fetchActiveConnectionsForStore(profileId, preferCache: false)
              .then((r) => PharmacyConnectionStore.instance
                  .mergeFirestoreConnections(r.items))
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Store pharmacy connections prefetch failed: $e\n$st');
          }),
          FirestoreService.instance.pharmacyFirestore
              .fetchDeliveriesForStore(profileId)
              .then((r) =>
                  PharmacyPrescriptionStore.instance.mergeFromFirestore(r))
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Store deliveries prefetch failed: $e\n$st');
          }),
        ]);
      case UserType.lab:
        await Future.wait([
          FirestoreService.instance.labConnection
              .fetchActiveConnectionsForLab(profileId, preferCache: false)
              .then((r) => LabConnectionStore.instance
                  .mergeFirestoreConnections(r.items))
              .catchError((e, st) {
            if (kDebugMode)
              debugPrint('Lab connections prefetch failed: $e\n$st');
          }),
          FirestoreService.instance.labOrder
              .fetchForLab(profileId, preferCache: false)
              .then((page) => LabWorklistStore.instance.mergeOrders(page.items))
              .catchError((e, st) {
            if (kDebugMode) debugPrint('Lab orders prefetch failed: $e\n$st');
          }),
          FirestoreService.instance.labBooking
              .fetchForLab(profileId)
              .then((bookings) =>
                  LabWorklistStore.instance.mergeBookings(bookings))
              .catchError((e, st) {
            if (kDebugMode) debugPrint('Lab bookings prefetch failed: $e\n$st');
          }),
        ]);
        break;
      case UserType.ambulance:
        break;
      case UserType.superAdmin:
        break;
    }
  }
}
