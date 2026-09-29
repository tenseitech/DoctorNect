import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/firebase/firestore_paths.dart';
import 'package:medibond/core/firebase/lab_report_file_store.dart';
import 'package:medibond/core/firebase/repositories/lab_booking_repository.dart';
import 'package:medibond/core/firebase/repositories/lab_order_repository.dart';
import 'package:medibond/core/security/file_encryption_service.dart';
import 'package:medibond/core/storage/profile_photo_uploader.dart';
import 'package:medibond/core/storage/s3_storage_service.dart';
import 'package:medibond/core/storage/storage_feature_flag.dart';
import 'package:medibond/core/storage/storage_service.dart';

class FailingFirestore extends FakeFirebaseFirestore {
  bool failOperations = false;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    if (failOperations) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Simulated Firestore connection error',
      );
    }
    return super.collection(collectionPath);
  }
}

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
  late FailingFirestore fakeFirestore;
  late Directory tempDir;

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    testS3 = TestS3StorageService();
    fakeFirestore = FailingFirestore();

    ProfilePhotoUploader.instance.firestoreOverride = fakeFirestore;
    ProfilePhotoUploader.instance.s3Override = testS3;

    LabBookingRepository.instance.firestoreOverride = fakeFirestore;
    LabOrderRepository.instance.firestoreOverride = fakeFirestore;
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
    ProfilePhotoUploader.instance.firestoreOverride = null;
    ProfilePhotoUploader.instance.s3Override = null;
    LabBookingRepository.instance.firestoreOverride = null;
    LabOrderRepository.instance.firestoreOverride = null;
    LabReportFileStore.s3Override = null;

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

    test('Success: S3 upload -> Firestore update -> Old S3 photo deleted',
        () async {
      final result = await ProfilePhotoUploader.instance.uploadPatientPhoto(
        patientId: patientId,
        bytes: sampleBytes,
        oldPhotoKey: oldKey,
        useS3Override: true,
      );

      expect(result.success, isTrue);
      expect(result.photoStorage, 's3');
      expect(result.photoKey, 'patient_profile/p_123/profile.jpg');
      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 1);
      expect(testS3.deletedKeys, contains(oldKey));

      final patientDoc = await fakeFirestore
          .collection(FirestorePaths.patients)
          .doc(patientId)
          .get();
      expect(patientDoc.exists, isTrue);
      expect(
          patientDoc.data()?['photoKey'], 'patient_profile/p_123/profile.jpg');
      expect(patientDoc.data()?['photoStorage'], 's3');

      final userDoc = await fakeFirestore
          .collection(FirestorePaths.users)
          .doc(patientId)
          .get();
      expect(userDoc.exists, isTrue);
      expect(userDoc.data()?['photoKey'], 'patient_profile/p_123/profile.jpg');
    });

    test('Firestore fails -> Old S3 photo is NOT deleted', () async {
      fakeFirestore.failOperations = true;

      await expectLater(
        ProfilePhotoUploader.instance.uploadPatientPhoto(
          patientId: patientId,
          bytes: sampleBytes,
          oldPhotoKey: oldKey,
          useS3Override: true,
        ),
        throwsA(isA<FirebaseException>()),
      );

      // S3 was uploaded, but because Firestore failed, old S3 object must NOT be deleted!
      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);
      expect(testS3.deletedKeys, isEmpty);
    });

    test(
        'S3 upload fails -> Firestore not updated, Old S3 photo is NOT deleted',
        () async {
      testS3.shouldFailUpload = true;

      await expectLater(
        ProfilePhotoUploader.instance.uploadPatientPhoto(
          patientId: patientId,
          bytes: sampleBytes,
          oldPhotoKey: oldKey,
          useS3Override: true,
        ),
        throwsException,
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);

      final patientDoc = await fakeFirestore
          .collection(FirestorePaths.patients)
          .doc(patientId)
          .get();
      expect(patientDoc.exists, isFalse);
    });
  });

  group('Doctor Profile Photo upload ordering', () {
    const doctorId = 'doc_456';
    const ownerUid = 'user_doc_456';
    const oldKey = 'doctor_profiles/doc_456/profile/old_pic.jpg';
    final sampleBytes = Uint8List.fromList([10, 20, 30, 40]);

    test('Success: S3 upload -> Firestore update -> Old S3 photo deleted',
        () async {
      final result = await ProfilePhotoUploader.instance.uploadDoctorPhoto(
        doctorId: doctorId,
        bytes: sampleBytes,
        oldPhotoKey: oldKey,
        ownerUid: ownerUid,
        useS3Override: true,
      );

      expect(result.success, isTrue);
      expect(result.photoStorage, 's3');
      expect(result.photoKey, 'doctor_profile/doc_456/profile.jpg');
      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 1);
      expect(testS3.deletedKeys, contains(oldKey));

      final docDoc = await fakeFirestore
          .collection(FirestorePaths.doctors)
          .doc(doctorId)
          .get();
      expect(docDoc.exists, isTrue);
      expect(docDoc.data()?['photoKey'], 'doctor_profile/doc_456/profile.jpg');

      final userDoc = await fakeFirestore
          .collection(FirestorePaths.users)
          .doc(ownerUid)
          .get();
      expect(userDoc.exists, isTrue);
      expect(userDoc.data()?['photoKey'], 'doctor_profile/doc_456/profile.jpg');
    });

    test('Firestore fails -> Old S3 photo is NOT deleted', () async {
      fakeFirestore.failOperations = true;

      await expectLater(
        ProfilePhotoUploader.instance.uploadDoctorPhoto(
          doctorId: doctorId,
          bytes: sampleBytes,
          oldPhotoKey: oldKey,
          ownerUid: ownerUid,
          useS3Override: true,
        ),
        throwsA(isA<FirebaseException>()),
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);
      expect(testS3.deletedKeys, isEmpty);
    });

    test(
        'S3 upload fails -> Firestore not updated, Old S3 photo is NOT deleted',
        () async {
      testS3.shouldFailUpload = true;

      await expectLater(
        ProfilePhotoUploader.instance.uploadDoctorPhoto(
          doctorId: doctorId,
          bytes: sampleBytes,
          oldPhotoKey: oldKey,
          ownerUid: ownerUid,
          useS3Override: true,
        ),
        throwsException,
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);

      final docDoc = await fakeFirestore
          .collection(FirestorePaths.doctors)
          .doc(doctorId)
          .get();
      expect(docDoc.exists, isFalse);
    });
  });

  group('LabBookingRepository.submitReport ordering', () {
    const bookingId = 'LAB_BOOK_101';
    const patientId = 'p_789';
    const oldReportKey = 'lab_reports/p_789/LAB_BOOK_101/old_report.pdf';
    final pdfBytes =
        Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 52]); // %PDF-1.4

    test('Success: S3 upload -> Firestore update -> Old S3 report deleted',
        () async {
      // Seed existing booking document in Firestore
      await fakeFirestore
          .collection(FirestorePaths.labBookings)
          .doc(bookingId)
          .set({
        'bookingId': bookingId,
        'patientId': patientId,
        'status': 'confirmed',
      });

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

      final updatedDoc = await fakeFirestore
          .collection(FirestorePaths.labBookings)
          .doc(bookingId)
          .get();
      expect(updatedDoc.data()?['status'], 'completed');
      expect(updatedDoc.data()?['reportStorageKey'], result.objectKey);
      expect(updatedDoc.data()?['reportStorageProvider'], 's3');
    });

    test('Firestore fails -> Old S3 report is NOT deleted', () async {
      // Intentionally do NOT seed the booking document so doc.update() throws FirebaseException (not found)
      await expectLater(
        LabBookingRepository.instance.submitReport(
          bookingId: bookingId,
          patientId: patientId,
          fileName: 'blood_test.pdf',
          bytes: pdfBytes,
          existingReportStorageKey: oldReportKey,
        ),
        throwsA(isA<FirebaseException>()),
      );

      // S3 upload succeeded, but Firestore update threw, so old S3 report must NOT be deleted!
      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);
      expect(testS3.deletedKeys, isEmpty);
    });

    test(
        'S3 upload fails -> Firestore not updated, Old S3 report is NOT deleted',
        () async {
      testS3.shouldFailUpload = true;

      await fakeFirestore
          .collection(FirestorePaths.labBookings)
          .doc(bookingId)
          .set({
        'bookingId': bookingId,
        'patientId': patientId,
        'status': 'confirmed',
      });

      await expectLater(
        LabBookingRepository.instance.submitReport(
          bookingId: bookingId,
          patientId: patientId,
          fileName: 'blood_test.pdf',
          bytes: pdfBytes,
          existingReportStorageKey: oldReportKey,
        ),
        throwsA(isA<StateError>()),
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);

      final doc = await fakeFirestore
          .collection(FirestorePaths.labBookings)
          .doc(bookingId)
          .get();
      expect(doc.data()?['status'], 'confirmed');
    });
  });

  group('LabOrderRepository.submitReport ordering', () {
    const orderId = 'ORDER_202';
    const patientId = 'p_888';
    const oldReportKey = 'lab_reports/p_888/ORDER_202/old_order_report.pdf';
    final pdfBytes =
        Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 52]); // %PDF-1.4

    test('Success: S3 upload -> Firestore update -> Old S3 report deleted',
        () async {
      // Seed existing order document in Firestore
      await fakeFirestore
          .collection(FirestorePaths.labOrders)
          .doc(orderId)
          .set({
        'orderId': orderId,
        'patientId': patientId,
        'status': 'ordered',
      });

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

      final updatedDoc = await fakeFirestore
          .collection(FirestorePaths.labOrders)
          .doc(orderId)
          .get();
      expect(updatedDoc.data()?['status'], 'completed');
      expect(updatedDoc.data()?['reportStorageKey'], result.objectKey);
      expect(updatedDoc.data()?['reportStorageProvider'], 's3');
    });

    test('Firestore fails -> Old S3 report is NOT deleted', () async {
      // Do NOT seed the order doc, so doc.update() throws FirebaseException
      await expectLater(
        LabOrderRepository.instance.submitReport(
          orderId: orderId,
          patientId: patientId,
          fileName: 'urine_culture.pdf',
          bytes: pdfBytes,
          existingReportStorageKey: oldReportKey,
        ),
        throwsA(isA<FirebaseException>()),
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);
      expect(testS3.deletedKeys, isEmpty);
    });

    test(
        'S3 upload fails -> Firestore not updated, Old S3 report is NOT deleted',
        () async {
      testS3.shouldFailUpload = true;

      await fakeFirestore
          .collection(FirestorePaths.labOrders)
          .doc(orderId)
          .set({
        'orderId': orderId,
        'patientId': patientId,
        'status': 'ordered',
      });

      await expectLater(
        LabOrderRepository.instance.submitReport(
          orderId: orderId,
          patientId: patientId,
          fileName: 'urine_culture.pdf',
          bytes: pdfBytes,
          existingReportStorageKey: oldReportKey,
        ),
        throwsA(isA<StateError>()),
      );

      expect(testS3.uploadCallCount, 1);
      expect(testS3.deleteCallCount, 0);

      final doc = await fakeFirestore
          .collection(FirestorePaths.labOrders)
          .doc(orderId)
          .get();
      expect(doc.data()?['status'], 'ordered');
    });
  });
}
