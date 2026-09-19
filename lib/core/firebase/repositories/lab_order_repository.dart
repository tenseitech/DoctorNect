import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase_bootstrap.dart';
import '../lab_report_file_store.dart';
import '../firestore_paths.dart';
import '../firestore_query_limits.dart';
import '../firestore_read_helper.dart';
import '../mappers/lab_order_firestore_mapper.dart';
import '../models/doctor_lab_order.dart';
import '../models/firestore_page.dart';
import 'patient_profile_repository.dart';

class LabOrderRepository {
  LabOrderRepository._();

  static final LabOrderRepository instance = LabOrderRepository._();

  Future<void> save(DoctorLabOrder order) async {
    if (!FirebaseBootstrap.isReady) return;

    await FirebaseFirestore.instance
        .collection(FirestorePaths.labOrders)
        .doc(order.orderId)
        .set({
      ...LabOrderFirestoreMapper.toMap(order),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<FirestorePage<DoctorLabOrder>> fetchForDoctor(
    String doctorId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.labOrdersPage,
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return const FirestorePage(items: [], hasMore: false);
    }

    final baseQuery = FirebaseFirestore.instance
        .collection(FirestorePaths.labOrders)
        .where('doctorId', isEqualTo: doctorId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    final query = startAfter == null
        ? baseQuery
        : baseQuery.startAfterDocument(startAfter);
    final snapshot = await FirestoreReadHelper.getQuery(
        query: query, preferCache: preferCache);

    final items = snapshot.docs
        .map((doc) => LabOrderFirestoreMapper.fromMap(doc.data()))
        .whereType<DoctorLabOrder>()
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return FirestorePage(
      items: items,
      lastDocument: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  Future<FirestorePage<DoctorLabOrder>> fetchForPatient(
    String patientId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.labOrdersPage,
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }

    final baseQuery = FirebaseFirestore.instance
        .collection(FirestorePaths.labOrders)
        .where('patientId', isEqualTo: patientId)
        .limit(limit);

    final query = startAfter == null
        ? baseQuery
        : baseQuery.startAfterDocument(startAfter);
    final snapshot = await FirestoreReadHelper.getQuery(
        query: query, preferCache: preferCache);

    final items = snapshot.docs
        .map((doc) => LabOrderFirestoreMapper.fromMap(doc.data()))
        .whereType<DoctorLabOrder>()
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return FirestorePage(
      items: items,
      lastDocument: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  /// Doctor-facing fetch — empty when the patient has turned off sharing.
  Future<FirestorePage<DoctorLabOrder>> fetchForPatientForDoctor(
    String patientId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.labOrdersPage,
    bool preferCache = true,
  }) async {
    if (patientId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }
    if (!await PatientProfileRepository.instance
        .isPatientSharingClinicalDataWithDoctors(
      patientId,
      preferCache: preferCache,
    )) {
      return const FirestorePage(items: [], hasMore: false);
    }
    return fetchForPatient(
      patientId,
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
    );
  }

  Future<FirestorePage<DoctorLabOrder>> fetchForLab(
    String labId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.labOrdersPage,
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady || labId.isEmpty) {
      return const FirestorePage(items: [], hasMore: false);
    }

    final baseQuery = FirebaseFirestore.instance
        .collection(FirestorePaths.labOrders)
        .where('labId',
            isEqualTo:
                labId) // FIXED: lab operators only see orders addressed to them
        .orderBy('createdAt', descending: true)
        .limit(limit);

    final query = startAfter == null
        ? baseQuery
        : baseQuery.startAfterDocument(startAfter);
    final snapshot = await FirestoreReadHelper.getQuery(
        query: query, preferCache: preferCache);

    final items = snapshot.docs
        .map((doc) => LabOrderFirestoreMapper.fromMap(doc.data()))
        .whereType<DoctorLabOrder>()
        .toList();

    return FirestorePage(
      items: items,
      lastDocument: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  Stream<List<DoctorLabOrder>> watchForLab(String labId) {
    if (!FirebaseBootstrap.isReady || labId.isEmpty)
      return const Stream.empty();

    return FirebaseFirestore.instance
        .collection(FirestorePaths.labOrders)
        .where('labId', isEqualTo: labId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => LabOrderFirestoreMapper.fromMap(doc.data()))
            .whereType<DoctorLabOrder>()
            .toList());
  }

  Stream<List<DoctorLabOrder>> watchForDoctor(String doctorId) {
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty)
      return const Stream.empty();

    return FirebaseFirestore.instance
        .collection(FirestorePaths.labOrders)
        .where('doctorId', isEqualTo: doctorId)
        .orderBy('createdAt', descending: true)
        .limit(FirestoreQueryLimits.labOrdersPage)
        .snapshots()
        .map((snap) {
      final items = snap.docs
          .map((doc) => LabOrderFirestoreMapper.fromMap(doc.data()))
          .whereType<DoctorLabOrder>()
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  Stream<List<DoctorLabOrder>> watchOrdersForDoctor(String doctorId) =>
      watchForDoctor(doctorId);

  Future<void> updateOrderStatus(String orderId, String status) async {
    if (!FirebaseBootstrap.isReady || orderId.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.labOrders)
        .doc(orderId)
        .update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> submitReport({
    required String orderId,
    required String patientId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!FirebaseBootstrap.isReady || orderId.isEmpty || patientId.isEmpty) {
      throw StateError('Firebase is not ready');
    }
    if (bytes.isEmpty || bytes.length > LabReportFileStore.maxFileBytes) {
      throw ArgumentError('Invalid report file size');
    }

    final storageUrl = await LabReportFileStore.uploadToStorage(
      patientId: patientId,
      bookingId: orderId, // We use orderId as the unique ID for storage
      fileName: fileName,
      bytes: bytes,
    );
    if (storageUrl == null || storageUrl.isEmpty) {
      throw StateError(
        'Could not upload report. Check Firebase Storage rules and your connection, then try again.',
      );
    }

    await LabReportFileStore.cacheLocally(
      patientId: patientId,
      bookingId: orderId,
      fileName: fileName,
      bytes: bytes,
    );

    await FirebaseFirestore.instance
        .collection(FirestorePaths.labOrders)
        .doc(orderId)
        .update({
      'status': 'completed',
      'reportFileName': fileName,
      'reportStorageUrl': storageUrl,
      'reportSubmittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 20));
    return storageUrl;
  }
}
