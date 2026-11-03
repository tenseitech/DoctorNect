import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../session/patient_session.dart';
import '../../storage/storage_service.dart';
import '../../supabase/repositories/supabase_lab_repository.dart';
import '../../../features/patient/lab/models/lab_models.dart';
import '../../../features/patient/lab/utils/patient_selected_investigations_mapper.dart';
import '../lab_report_file_store.dart';
import '../lab_report_submit_flow.dart';

/// Patient lab booking as seen by the lab operator.
class LabBookingRecord {
  const LabBookingRecord({
    required this.bookingId,
    required this.patientId,
    required this.patientName,
    required this.testName,
    this.testNames = const [],
    this.groupedBookingIds = const [],
    required this.dateTime,
    required this.slotLabel,
    required this.collectionType,
    required this.address,
    required this.status,
    this.labId,
    this.labName,
    this.reportFileName,
    this.reportStorageUrl,
    this.reportStorageKey,
    this.reportStorageProvider,
    this.reportSubmittedAt,
    this.reportBookingId,
    this.createdAt,
  });

  final String bookingId;
  final String? labId;
  final String? labName;
  final String patientId;
  final String patientName;
  final String testName;
  final List<String> testNames;
  final List<String> groupedBookingIds;
  final DateTime dateTime;
  final String slotLabel;
  final String collectionType;
  final String address;
  final String status;
  final String? reportFileName;
  final String? reportStorageUrl;
  final String? reportStorageKey;
  final String? reportStorageProvider;
  final DateTime? reportSubmittedAt;
  final String? reportBookingId;
  final DateTime? createdAt;

  bool get hasReport =>
      reportFileName != null &&
      reportFileName!.trim().isNotEmpty &&
      ((reportStorageKey != null && reportStorageKey!.trim().isNotEmpty) ||
          (reportStorageUrl != null && reportStorageUrl!.trim().isNotEmpty));

  String get reportOwnerBookingId => reportBookingId?.trim().isNotEmpty == true
      ? reportBookingId!.trim()
      : bookingId;

  List<String> get allTestNames {
    if (testNames.isNotEmpty) return testNames;
    final single = testName.trim();
    return single.isEmpty ? const ['Lab test'] : [single];
  }

  String get displayTestName => allTestNames.length > 1
      ? PatientSelectedInvestigationsMapper.summaryFromNames(allTestNames)
      : testName;

  List<String> get linkedBookingIds =>
      groupedBookingIds.isNotEmpty ? groupedBookingIds : [bookingId];
}

class LabBookingRepository {
  LabBookingRepository._();

  static final LabBookingRepository instance = LabBookingRepository._();

  /// Legacy test hook — Postgres-only; ignored at runtime.
  @visibleForTesting
  dynamic firestoreOverride;

  static String newBookingId({int suffix = 0}) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return 'LAB$stamp$suffix';
  }

  Future<LabBookingRecord> save({
    required String patientId,
    required LabBookingDraft draft,
    required List<LabTestItem> tests,
    required String bookingId,
    String status = 'confirmed',
    String? familyMemberId,
  }) async {
    if (draft.selectedDate == null || draft.selectedSlotLabel == null) {
      throw StateError('Booking date and time are required');
    }
    if (tests.isEmpty) {
      throw StateError('At least one test is required');
    }

    final date = draft.selectedDate!;
    final dateTime = LabSlotTime.combine(date, draft.selectedSlotLabel!);
    final testNames = tests
        .map((test) => test.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    final summary = PatientSelectedInvestigationsMapper.summaryFromNames(
      testNames,
    );

    final record = LabBookingRecord(
      bookingId: bookingId,
      labId: draft.selectedLab?.id,
      labName: draft.selectedLab?.name,
      patientId: patientId,
      patientName: draft.patientName,
      testName: summary,
      testNames: testNames,
      dateTime: dateTime,
      slotLabel: draft.selectedSlotLabel!,
      collectionType: draft.collectionType.name,
      address: draft.address ?? '',
      status: status,
      createdAt: DateTime.now(),
    );

    await SupabaseLabRepository.instance.saveBooking(record);
    return record;
  }

  Future<LabBookingRecord> saveWalkInBooking({
    required String labId,
    required String labName,
    required String patientName,
    required int patientAge,
    required String patientGender,
    required List<String> testNames,
    String? contactNumber,
  }) async {
    if (labId.isEmpty) {
      throw ArgumentError('Lab id is required');
    }
    final trimmedTests =
        testNames.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    if (trimmedTests.isEmpty) {
      throw ArgumentError('At least one test is required');
    }

    final bookingId = newBookingId();
    final patientId = 'wi${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
    final slotLabel = LabSlotTime.format(TimeOfDay.fromDateTime(now));
    final dateTime = LabSlotTime.combine(now, slotLabel);
    final summary = PatientSelectedInvestigationsMapper.summaryFromNames(
      trimmedTests,
    );

    final record = LabBookingRecord(
      bookingId: bookingId,
      labId: labId,
      labName: labName,
      patientId: patientId,
      patientName: patientName.trim(),
      testName: summary,
      testNames: trimmedTests,
      dateTime: dateTime,
      slotLabel: slotLabel,
      collectionType: LabCollectionType.walkIn.name,
      address: '',
      status: 'confirmed',
      createdAt: now,
    );

    await SupabaseLabRepository.instance.saveBooking(record);
    return record;
  }

  Future<Set<String>> bookedSlotLabelsForDate(DateTime date) async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return {};
    return SupabaseLabRepository.instance.bookedSlotLabelsForPatientOnDate(
      patientId,
      date,
    );
  }

  Future<List<String>> availableSlotsForPeriod({
    required DateTime date,
    required String period,
    required Map<String, List<String>> slotPeriods,
  }) async {
    final all = slotPeriods[period] ?? const [];
    final booked = await bookedSlotLabelsForDate(date);
    return all.where((slot) => !booked.contains(slot)).toList();
  }

  Future<List<LabBookingRecord>> fetchForPatient(
    String patientId, {
    bool preferCache = true,
  }) async {
    return SupabaseLabRepository.instance.fetchBookingsForPatient(patientId);
  }

  Future<List<LabBookingRecord>> fetchForLab(String labId) async {
    return SupabaseLabRepository.instance.fetchBookingsForLab(labId);
  }

  Stream<List<LabBookingRecord>> watchForLab(String labId) {
    return SupabaseLabRepository.instance.watchBookingsForLab(labId);
  }

  Stream<List<LabBookingRecord>> watchForPatient(String patientId) {
    return SupabaseLabRepository.instance.watchBookingsForPatient(patientId);
  }

  Future<void> updateBookingStatus(String bookingId, String status) async {
    await SupabaseLabRepository.instance.updateLabBookingStatus(
      bookingId: bookingId,
      newStatus: status,
    );
  }

  Future<StorageUploadResult> submitReport({
    required String bookingId,
    required String patientId,
    required String fileName,
    required Uint8List bytes,
    List<String> linkedBookingIds = const [],
    String? existingReportStorageKey,
  }) async {
    if (bookingId.trim().isEmpty) {
      throw ArgumentError('bookingId cannot be empty');
    }
    if (patientId.trim().isEmpty) {
      throw ArgumentError('patientId cannot be empty');
    }
    if (bytes.isEmpty) {
      throw ArgumentError('Report file cannot be empty');
    }

    LabReportSubmitFlow.ensureSupabaseReady();

    final uploadResult = await LabReportFileStore.uploadReport(
      patientId: patientId,
      bookingId: bookingId,
      fileName: fileName,
      bytes: bytes,
    );
    if (uploadResult == null) {
      throw StateError(
        'Could not upload report. Check storage rules and your connection, then try again.',
      );
    }

    await LabReportSubmitFlow.finalizeAfterUpload(
      uploadResult: uploadResult,
      existingReportStorageKey: existingReportStorageKey,
      persistToDatabase: () async {
        for (final id in {
          bookingId,
          ...linkedBookingIds,
        }.where((id) => id.trim().isNotEmpty)) {
          final ok = await SupabaseLabRepository.instance.updateLabBookingStatus(
            bookingId: id,
            newStatus: 'completed',
            notes: uploadResult.objectKey,
          );
          if (!ok) return false;
        }
        return true;
      },
      cacheLocally: () => LabReportFileStore.cacheLocally(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        bytes: bytes,
        storageKey: uploadResult.objectKey,
      ),
    );

    return uploadResult;
  }
}
