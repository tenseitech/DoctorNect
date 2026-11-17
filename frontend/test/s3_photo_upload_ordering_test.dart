import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/firebase/lab_report_file_store.dart';
import 'package:medibond/core/firebase/repositories/lab_booking_repository.dart';
import 'package:medibond/core/firebase/repositories/lab_order_repository.dart';
import 'package:medibond/core/security/file_encryption_service.dart';
import 'package:medibond/core/storage/profile_photo_uploader.dart';
import 'package:medibond/core/storage/s3_storage_service.dart';
import 'package:medibond/core/storage/storage_feature_flag.dart';
import 'package:medibond/core/firebase/lab_report_submit_flow.dart';
import 'package:medibond/core/storage/storage_service.dart';
import 'package:medibond/core/supabase/repositories/supabase_lab_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

class TestS3StorageService extends S3StorageService {
  bool shouldFailUpload = false;
  int uploadCallCount = 0;
  int deleteCallCount = 0;
  final List<String> deletedKeys = [];
  String? lastUploadedPurpose;
  String? lastUploadedParentId;
  String? lastUploadedFileName;

  @override
  Future<StorageUploadResult> uploadBytes({
    required String purpose,
    required String parentId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    uploadCallCount++;
    lastUploadedPurpose = purpose;
    lastUploadedParentId = parentId;
    lastUploadedFileName = fileName;

    if (shouldFailUpload) {
      throw Exception('Simulated S3 upload failure');
    }

    final key = '$purpose/$parentId/$fileName';
    return StorageUploadResult(
      objectKey: key,
      downloadUrl: 'https://s3.example.com/$key',
      provider: 's3',
    );
  }

  @override
  Future<bool> deleteObject(String keyOrUrl) async {
    deleteCallCount++;
    deletedKeys.add(keyOrUrl);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestS3StorageService testS3;
  late Directory tempDir;

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    testS3 = TestS3StorageService();
    ProfilePhotoUploader.instance.s3Override = testS3;

    LabBookingRepository.instance.firestoreOverride = null;
    LabOrderRepository.instance.firestoreOverride = null;
    LabReportFileStore.s3Override = testS3;

    StorageFeatureFlag.debugOverride = true;
    FileEncryptionService.setKeyForTesting();

    tempDir = Directory.systemTemp.createTempSync('s3_ordering_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() {
    ProfilePhotoUploader.instance.s3Override = null;
    LabBookingRepository.instance.firestoreOverride = null;
    LabOrderRepository.instance.firestoreOverride = null;
    LabReportFileStore.s3Override = null;
    SupabaseLabRepository.debugResetForTesting();
    SupabaseBootstrap.isReady = false;

    StorageFeatureFlag.debugOverride = null;
    FileEncryptionService.resetForTesting();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Patient Profile Photo upload ordering', () {
    const patientId = 'p_123';
    const oldKey = 'patients/p_123/profile/old_avatar.jpg';
    final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    var persistCalls = 0;
    var persistFails = false;

    setUp(() {
      persistCalls = 0;
      persistFails = false;
      SupabaseBootstrap.isReady = true;
      ProfilePhotoUploader.debugPersistPatient = ({
        required String patientId,
        required String newObjectKey,
      }) async {
        persistCalls++;
        if (persistFails) throw StateError('persist failed');
      };
    });

    tearDown(() {
      ProfilePhotoUploader.debugPersistPatient = null;
    });

    test('Success: S3 upload -> metadata persist -> Old S3 photo deleted',
        () async {
      final result = await ProfilePhotoUploader.instance.uploadPatientPhoto(
        patientId: patientId,
        bytes: sampleBytes,
        oldPhotoKey: oldKey,
        useS3Override: true,
      );

      expect(result.success, isTrue);
      expect(persistCalls, 1);
      expect(testS3.deleteCallCount, 1);
    });

    test('Metadata persist fails -> Old S3 photo is NOT deleted', () async {
      persistFails = true;
      await expectLater(
        ProfilePhotoUploader.instance.uploadPatientPhoto(
          patientId: patientId,
          bytes: sampleBytes,
          oldPhotoKey: oldKey,
          useS3Override: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(testS3.deleteCallCount, 0);
    });
  });

  group('Doctor Profile Photo upload ordering', () {
    const doctorId = 'doc_456';
    const ownerUid = 'user_doc_456';
    const oldKey = 'doctor_profiles/doc_456/profile/old_pic.jpg';
    final sampleBytes = Uint8List.fromList([10, 20, 30, 40]);
    var persistCalls = 0;
    var persistFails = false;

    setUp(() {
      persistCalls = 0;
      persistFails = false;
      SupabaseBootstrap.isReady = true;
      ProfilePhotoUploader.debugPersistDoctor = ({
        required String doctorId,
        required String? ownerUid,
        required String newObjectKey,
      }) async {
        persistCalls++;
        if (persistFails) throw StateError('persist failed');
      };
    });

    tearDown(() {
      ProfilePhotoUploader.debugPersistDoctor = null;
    });

    test('Success: S3 upload -> metadata persist -> Old S3 photo deleted',
        () async {
      final result = await ProfilePhotoUploader.instance.uploadDoctorPhoto(
        doctorId: doctorId,
        bytes: sampleBytes,
        oldPhotoKey: oldKey,
        ownerUid: ownerUid,
        useS3Override: true,
      );

      expect(result.success, isTrue);
      expect(persistCalls, 1);
      expect(testS3.deleteCallCount, 1);
    });
  });

  group('LabBookingRepository.submitReport ordering', () {
    setUp(() {
      SupabaseLabRepository.debugPersistLabBookingReportKeyOverride =
          (_, __) async {};
      SupabaseLabRepository.debugClearLabBookingReportKeyOverride =
          (_) async {};
    });

    const bookingId = 'LAB_BOOK_101';
    const patientId = 'p_789';
    const oldReportKey = 'lab_reports/p_789/LAB_BOOK_101/old_report.pdf';
    final pdfBytes =
        Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 52]); // %PDF-1.4

    test('throws before upload when Supabase is not ready', () async {
      SupabaseBootstrap.isReady = false;

      await expectLater(
        LabBookingRepository.instance.submitReport(
          bookingId: bookingId,
          patientId: patientId,
          fileName: 'blood_test.pdf',
          bytes: pdfBytes,
          existingReportStorageKey: oldReportKey,
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.message == LabReportSubmitFlow.notReadyMessage,
          ),
        ),
      );

      expect(testS3.uploadCallCount, 0);
    });

    test('RPC failure after upload deletes new object and keeps old key',
        () async {
      SupabaseBootstrap.isReady = true;
      SupabaseLabRepository.debugUpdateLabBookingStatusOverride =
          ({required bookingId, required newStatus, notes}) async => false;

      await expectLater(
        LabBookingRepository.instance.submitReport(
          bookingId: bookingId,
          patientId: patientId,
          fileName: 'blood_test.pdf',
          bytes: pdfBytes,
          existingReportStorageKey: oldReportKey,
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.message == LabReportSubmitFlow.persistFailedMessage,
          ),
        ),
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 1);
      expect(testS3.deletedKeys, isNot(contains(oldReportKey)));
    });

    test('success deletes old report only after RPC succeeds', () async {
      SupabaseBootstrap.isReady = true;
      SupabaseLabRepository.debugUpdateLabBookingStatusOverride =
          ({required bookingId, required newStatus, notes}) async => true;

      final result = await LabBookingRepository.instance.submitReport(
        bookingId: bookingId,
        patientId: patientId,
        fileName: 'blood_test.pdf',
        bytes: pdfBytes,
        existingReportStorageKey: oldReportKey,
      );

      expect(result.provider, 's3');
      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 1);
      expect(testS3.deletedKeys, contains(oldReportKey));
    });
  });

  group('LabOrderRepository.submitReport ordering', () {
    setUp(() {
      SupabaseLabRepository.debugPersistLabOrderReportKeyOverride =
          (_, __) async {};
      SupabaseLabRepository.debugClearLabOrderReportKeyOverride = (_) async {};
    });

    const orderId = 'ORDER_202';
    const patientId = 'p_888';
    const oldReportKey = 'lab_reports/p_888/ORDER_202/old_order_report.pdf';
    final pdfBytes =
        Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 52]); // %PDF-1.4

    test('throws before upload when Supabase is not ready', () async {
      SupabaseBootstrap.isReady = false;

      await expectLater(
        LabOrderRepository.instance.submitReport(
          orderId: orderId,
          patientId: patientId,
          fileName: 'urine_culture.pdf',
          bytes: pdfBytes,
          existingReportStorageKey: oldReportKey,
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.message == LabReportSubmitFlow.notReadyMessage,
          ),
        ),
      );

      expect(testS3.uploadCallCount, 0);
    });

    test('RPC failure after upload deletes new object and keeps old key',
        () async {
      SupabaseBootstrap.isReady = true;
      SupabaseLabRepository.debugUpdateLabOrderStatusOverride =
          ({required orderId, required newStatus, notes}) async => false;

      await expectLater(
        LabOrderRepository.instance.submitReport(
          orderId: orderId,
          patientId: patientId,
          fileName: 'urine_culture.pdf',
          bytes: pdfBytes,
          existingReportStorageKey: oldReportKey,
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.message == LabReportSubmitFlow.persistFailedMessage,
          ),
        ),
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 1);
      expect(testS3.deletedKeys, isNot(contains(oldReportKey)));
    });

    test('success deletes old report only after RPC succeeds', () async {
      SupabaseBootstrap.isReady = true;
      SupabaseLabRepository.debugUpdateLabOrderStatusOverride =
          ({required orderId, required newStatus, notes}) async => true;

      final result = await LabOrderRepository.instance.submitReport(
        orderId: orderId,
        patientId: patientId,
        fileName: 'urine_culture.pdf',
        bytes: pdfBytes,
        existingReportStorageKey: oldReportKey,
      );

      expect(result.provider, 's3');
      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 1);
      expect(testS3.deletedKeys, contains(oldReportKey));
    });
  });
}
