import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../storage/storage_service.dart';
import '../../supabase/repositories/supabase_lab_repository.dart';
import '../../supabase/supabase_bootstrap.dart';
import '../firestore_query_limits.dart';
import '../lab_report_file_store.dart';
import '../models/doctor_lab_order.dart';
import '../models/firestore_page.dart';

class LabOrderRepository {
  LabOrderRepository._();

  static final LabOrderRepository instance = LabOrderRepository._();

  /// Legacy test hook — Postgres-only; ignored at runtime.
  @visibleForTesting
  dynamic firestoreOverride;

  Future<void> save(DoctorLabOrder order) async {
    return SupabaseLabRepository.instance.saveOrder(order);
  }

  Future<FirestorePage<DoctorLabOrder>> fetchForDoctor(
    String doctorId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.labOrdersPage,
    bool preferCache = true,
  }) async {
    return SupabaseLabRepository.instance
        .fetchOrdersForDoctor(doctorId, limit: limit);
  }

  Future<FirestorePage<DoctorLabOrder>> fetchForPatient(
    String patientId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.labOrdersPage,
    bool preferCache = true,
  }) async {
    return SupabaseLabRepository.instance
        .fetchOrdersForPatient(patientId, limit: limit);
  }

  Future<FirestorePage<DoctorLabOrder>> fetchForPatientForDoctor(
    String patientId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.labOrdersPage,
    bool preferCache = true,
  }) async {
    return SupabaseLabRepository.instance
        .fetchOrdersForPatient(patientId, limit: limit);
  }

  Future<FirestorePage<DoctorLabOrder>> fetchForLab(
    String labId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.labOrdersPage,
    bool preferCache = true,
  }) async {
    final orders =
        await SupabaseLabRepository.instance.fetchOrdersForLab(labId);
    return FirestorePage(items: orders, hasMore: false);
  }

  Stream<List<DoctorLabOrder>> watchForLab(String labId) {
    return SupabaseLabRepository.instance.watchOrdersForLab(labId);
  }

  Stream<List<DoctorLabOrder>> watchForDoctor(String doctorId) {
    return SupabaseLabRepository.instance.watchOrdersForDoctor(doctorId);
  }

  Stream<List<DoctorLabOrder>> watchOrdersForDoctor(String doctorId) =>
      watchForDoctor(doctorId);

  Future<void> updateOrderStatus(String orderId, String status) async {
    await SupabaseLabRepository.instance.updateLabOrderStatus(
      orderId: orderId,
      newStatus: status,
    );
  }

  Future<StorageUploadResult> submitReport({
    required String orderId,
    required String patientId,
    required String fileName,
    required Uint8List bytes,
    String? existingReportStorageKey,
  }) async {
    if (orderId.isEmpty || patientId.isEmpty) {
      throw ArgumentError('orderId and patientId are required');
    }
    if (bytes.isEmpty || bytes.length > LabReportFileStore.maxFileBytes) {
      throw ArgumentError('Invalid report file size');
    }

    final uploadResult = await LabReportFileStore.uploadReport(
      patientId: patientId,
      bookingId: orderId,
      fileName: fileName,
      bytes: bytes,
    );
    if (uploadResult == null) {
      throw StateError(
        'Could not upload report. Check storage rules and your connection, then try again.',
      );
    }

    await LabReportFileStore.cacheLocally(
      patientId: patientId,
      bookingId: orderId,
      fileName: fileName,
      bytes: bytes,
      storageKey: uploadResult.objectKey,
    );

    if (SupabaseBootstrap.isReady) {
      await SupabaseLabRepository.instance.updateLabOrderStatus(
        orderId: orderId,
        newStatus: 'completed',
        notes: uploadResult.objectKey,
      );
      if (existingReportStorageKey != null &&
          existingReportStorageKey.trim().isNotEmpty &&
          existingReportStorageKey != uploadResult.objectKey) {
        await LabReportFileStore.deleteS3Report(existingReportStorageKey);
      }
    }

    return uploadResult;
  }
}
