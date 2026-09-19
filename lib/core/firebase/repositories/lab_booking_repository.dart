import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../../features/patient/lab/models/lab_models.dart';
import '../../../features/patient/lab/utils/patient_selected_investigations_mapper.dart';
import '../lab_report_file_store.dart';
import '../../session/patient_session.dart'; // FIXED: scope slot queries to the current patient
import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_read_helper.dart';

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
  final DateTime? reportSubmittedAt;

  /// Booking row that owns the uploaded report file (may differ in grouped checkouts).
  final String? reportBookingId;
  final DateTime? createdAt;

  bool get hasReport =>
      reportFileName != null &&
      reportFileName!.trim().isNotEmpty &&
      reportStorageUrl != null &&
      reportStorageUrl!.trim().isNotEmpty;

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
    if (!FirebaseBootstrap.isReady) {
      throw StateError('Firebase is not ready');
    }
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
    final testIds = tests.map((test) => test.id).toList();
    final summary =
        PatientSelectedInvestigationsMapper.summaryFromNames(testNames);

    await FirebaseFirestore.instance
        .collection(FirestorePaths.labBookings)
        .doc(bookingId)
        .set({
      'bookingId': bookingId,
      'patientId': patientId,
      'testId': testIds.first,
      'testIds': testIds,
      'testName': summary,
      'testNames': testNames,
      'patientName': draft.patientName,
      'patientAge': draft.patientAge,
      'bookingForSelf': draft.bookingForSelf,
      if (familyMemberId != null && familyMemberId.isNotEmpty)
        'familyMemberId': familyMemberId,
      'collectionType': draft.collectionType.name,
      'partnerLab': draft.selectedLab?.name ?? '',
      if (draft.selectedLab?.id != null && draft.selectedLab!.id!.isNotEmpty)
        'labId': draft.selectedLab!
            .id, // FIXED: persist labId so the lab operator can query their bookings
      'address': draft.address ?? '',
      'dateTime': Timestamp.fromDate(dateTime),
      'slotLabel': draft.selectedSlotLabel,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return LabBookingRecord(
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
  }

  /// Registers a walk-in patient at the lab counter (no patient app account).
  Future<LabBookingRecord> saveWalkInBooking({
    required String labId,
    required String labName,
    required String patientName,
    required int patientAge,
    required String patientGender,
    required List<String> testNames,
    String? contactNumber,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      throw StateError('Firebase is not ready');
    }
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
    final summary =
        PatientSelectedInvestigationsMapper.summaryFromNames(trimmedTests);

    await FirebaseFirestore.instance
        .collection(FirestorePaths.labBookings)
        .doc(bookingId)
        .set({
      'bookingId': bookingId,
      'patientId': patientId,
      'patientName': patientName.trim(),
      'patientAge': patientAge,
      'patientGender': AppConstants.normalizePatientGender(patientGender),
      if (contactNumber != null && contactNumber.trim().isNotEmpty)
        'contactNumber': contactNumber.trim(),
      'testName': summary,
      'testNames': trimmedTests,
      'testId':
          trimmedTests.first.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      'testIds': trimmedTests
          .map((t) => t.toLowerCase().replaceAll(RegExp(r'\s+'), '_'))
          .toList(),
      'collectionType': LabCollectionType.walkIn.name,
      'partnerLab': labName,
      'labId': labId,
      'address': '',
      'dateTime': Timestamp.fromDate(dateTime),
      'slotLabel': slotLabel,
      'status': 'confirmed',
      'source': 'walkin',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return LabBookingRecord(
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
  }

  Future<Set<String>> bookedSlotLabelsForDate(DateTime date) async {
    if (!FirebaseBootstrap.isReady) return {};

    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty)
      return {}; // FIXED: no patient context, nothing to query

    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final snapshot = await FirestoreReadHelper.getQuery(
      // FIXED: filter by patientId so the query satisfies Firestore rules (patients can't read others' bookings)
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.labBookings)
          .where('patientId', isEqualTo: patientId)
          .where('dateTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('dateTime', isLessThan: Timestamp.fromDate(dayEnd)),
    );

    return snapshot.docs
        .map((doc) => doc.data()['slotLabel'] as String? ?? '')
        .where((label) => label.isNotEmpty)
        .toSet();
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
    if (!FirebaseBootstrap.isReady || patientId.isEmpty) return const [];

    final snapshot = await FirestoreReadHelper.getQuery(
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.labBookings)
          .where('patientId', isEqualTo: patientId)
          .orderBy('dateTime', descending: true)
          .limit(100),
      preferCache: preferCache,
    );

    return snapshot.docs
        .map((doc) => _fromMap(doc.id, doc.data()))
        .whereType<LabBookingRecord>()
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  Future<List<LabBookingRecord>> fetchForLab(String labId) async {
    if (!FirebaseBootstrap.isReady || labId.isEmpty) return const [];

    final snapshot = await FirestoreReadHelper.getQuery(
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.labBookings)
          .where('labId', isEqualTo: labId)
          .orderBy('dateTime', descending: true)
          .limit(100),
    );

    return snapshot.docs
        .map((doc) => _fromMap(doc.id, doc.data()))
        .whereType<LabBookingRecord>()
        .toList();
  }

  Stream<List<LabBookingRecord>> watchForLab(String labId) {
    if (!FirebaseBootstrap.isReady || labId.isEmpty)
      return const Stream.empty();

    return FirebaseFirestore.instance
        .collection(FirestorePaths.labBookings)
        .where('labId', isEqualTo: labId)
        .orderBy('dateTime', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => _fromMap(doc.id, doc.data()))
            .whereType<LabBookingRecord>()
            .toList());
  }

  Stream<List<LabBookingRecord>> watchForPatient(String patientId) {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty)
      return const Stream.empty();

    return FirebaseFirestore.instance
        .collection(FirestorePaths.labBookings)
        .where('patientId', isEqualTo: patientId)
        .orderBy('dateTime', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => _fromMap(doc.id, doc.data()))
            .whereType<LabBookingRecord>()
            .toList());
  }

  Future<void> updateBookingStatus(String bookingId, String status) async {
    if (!FirebaseBootstrap.isReady || bookingId.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.labBookings)
        .doc(bookingId)
        .update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> submitReport({
    required String bookingId,
    required String patientId,
    required String fileName,
    required Uint8List bytes,
    List<String> linkedBookingIds = const [],
  }) async {
    if (!FirebaseBootstrap.isReady || bookingId.isEmpty || patientId.isEmpty) {
      throw StateError('Firebase is not ready');
    }
    if (bytes.isEmpty || bytes.length > LabReportFileStore.maxFileBytes) {
      throw ArgumentError('Invalid report file size');
    }

    final storageUrl = await LabReportFileStore.uploadToStorage(
      patientId: patientId,
      bookingId: bookingId,
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
      bookingId: bookingId,
      fileName: fileName,
      bytes: bytes,
    );

    final updatePayload = {
      'status': 'completed',
      'reportFileName': fileName,
      'reportStorageUrl': storageUrl,
      'reportBookingId': bookingId,
      'reportSubmittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final bookingIds = {
      bookingId,
      ...linkedBookingIds,
    }.where((id) => id.trim().isNotEmpty).toList();

    if (bookingIds.length == 1) {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.labBookings)
          .doc(bookingIds.first)
          .update(updatePayload)
          .timeout(const Duration(seconds: 20));
    } else {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in bookingIds) {
        batch.update(
          FirebaseFirestore.instance
              .collection(FirestorePaths.labBookings)
              .doc(id),
          updatePayload,
        );
      }
      await batch.commit().timeout(const Duration(seconds: 20));
    }

    return storageUrl;
  }

  LabBookingRecord? _fromMap(String docId, Map<String, dynamic> data) {
    try {
      final dateTime =
          (data['dateTime'] as Timestamp?)?.toDate() ?? DateTime.now();
      final testNamesRaw = data['testNames'];
      final testNames = testNamesRaw is List
          ? testNamesRaw
              .map((item) => item.toString().trim())
              .where((name) => name.isNotEmpty)
              .toList()
          : <String>[];
      final testName = data['testName'] as String? ??
          (testNames.isNotEmpty
              ? PatientSelectedInvestigationsMapper.summaryFromNames(testNames)
              : 'Lab test');

      return LabBookingRecord(
        bookingId: data['bookingId'] as String? ?? docId,
        labId: data['labId'] as String?,
        labName: data['partnerLab'] as String?,
        patientId: data['patientId'] as String? ?? '',
        patientName: data['patientName'] as String? ?? 'Patient',
        testName: testName,
        testNames: testNames,
        dateTime: dateTime,
        slotLabel: data['slotLabel'] as String? ?? '',
        collectionType: data['collectionType'] as String? ?? 'home',
        address: data['address'] as String? ?? '',
        status: data['status'] as String? ?? 'confirmed',
        reportFileName: data['reportFileName'] as String?,
        reportStorageUrl: data['reportStorageUrl'] as String?,
        reportSubmittedAt: (data['reportSubmittedAt'] as Timestamp?)?.toDate(),
        reportBookingId: data['reportBookingId'] as String? ?? docId,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      );
    } catch (_) {
      return null;
    }
  }
}
