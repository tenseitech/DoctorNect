import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medibond/core/firebase/lab_report_file_store.dart';
import 'package:medibond/core/security/file_encryption_service.dart';
import 'package:medibond/core/storage/s3_storage_service.dart';
import 'package:medibond/core/storage/storage_feature_flag.dart';
import 'package:medibond/core/storage/storage_service.dart';

class FakeS3StorageService extends S3StorageService {
  int uploadCallCount = 0;
  int getDownloadUrlCallCount = 0;
  int deleteCallCount = 0;
  String? lastUploadedPurpose;
  String? lastUploadedParentId;
  String? lastUploadedFileName;
  Uint8List? lastUploadedBytes;
  String? lastRequestedKey;
  String? lastDeletedKey;

  String? downloadUrlToReturn;
  StorageUploadResult? uploadResultToReturn;

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
    lastUploadedBytes = bytes;
    onProgress?.call(bytes.length, bytes.length);
    return uploadResultToReturn ??
        StorageUploadResult(
          objectKey: 'lab_reports/$parentId/$fileName',
          downloadUrl: null,
          provider: 's3',
        );
  }

  @override
  Future<String?> getDownloadUrl(String keyOrUrl) async {
    getDownloadUrlCallCount++;
    lastRequestedKey = keyOrUrl;
    return downloadUrlToReturn ??
        'https://s3.ap-south-1.amazonaws.com/doctornect/$keyOrUrl?presigned=1';
  }

  @override
  Future<bool> deleteObject(String keyOrUrl) async {
    deleteCallCount++;
    lastDeletedKey = keyOrUrl;
    return true;
  }
}

class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this._handler);
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  int callCount = 0;
  Uri? lastUri;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    lastUri = request.url;
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeS3StorageService fakeS3;
  late S3StorageService originalS3Instance;
  late Directory tempDir;

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    originalS3Instance = S3StorageService.instance;
    fakeS3 = FakeS3StorageService();
    S3StorageService.instance = fakeS3;

    FileEncryptionService.setKeyForTesting();

    tempDir = Directory.systemTemp.createTempSync('lab_report_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    StorageFeatureFlag.debugOverride = null;
    LabReportFileStore.httpClient = null;
    LabReportFileStore.mockDownloadFromUrl = null;
    LabReportFileStore.mockFirebaseUpload = null;
  });

  tearDown(() {
    S3StorageService.instance = originalS3Instance;
    FileEncryptionService.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }

    StorageFeatureFlag.debugOverride = null;
    LabReportFileStore.httpClient = null;
    LabReportFileStore.mockDownloadFromUrl = null;
    LabReportFileStore.mockFirebaseUpload = null;
  });

  group('LabReportFileStore Routing & Feature Flag', () {
    const patientId = 'p_test_123';
    const bookingId = 'booking_test_456';
    const fileName = 'Complete_Blood_Count_Lab_Report.pdf';
    // Valid PDF header "%PDF-1.4..."
    final samplePdfBytes = Uint8List.fromList(
        utf8.encode('%PDF-1.4 sample pdf content for lab testing'));

    test('flag OFF: uploads to Firebase Storage, S3 is NOT called', () async {
      StorageFeatureFlag.debugOverride = false;

      var firebaseUploadCalled = false;
      LabReportFileStore.mockFirebaseUpload = (pId, bId, fName, bytes) async {
        firebaseUploadCalled = true;
        expect(pId, equals(patientId));
        expect(bId, equals(bookingId));
        expect(fName, equals(fileName));
        expect(bytes, equals(samplePdfBytes));
        return 'https://firebasestorage.googleapis.com/v0/b/test/o/lab_report.pdf';
      };

      final result = await LabReportFileStore.uploadReport(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        bytes: samplePdfBytes,
      );

      expect(result, isNotNull);
      expect(result!.provider, equals('firebase'));
      expect(result.downloadUrl, contains('firebasestorage.googleapis.com'));
      expect(firebaseUploadCalled, isTrue);
      expect(fakeS3.uploadCallCount, equals(0));
    });

    test(
        'flag ON: uploads via S3StorageService with parentId="{patientId}/{bookingId}"',
        () async {
      StorageFeatureFlag.debugOverride = true;

      var firebaseUploadCalled = false;
      LabReportFileStore.mockFirebaseUpload = (pId, bId, fName, bytes) async {
        firebaseUploadCalled = true;
        return 'https://firebasestorage.googleapis.com/unexpected';
      };

      final result = await LabReportFileStore.uploadReport(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        bytes: samplePdfBytes,
      );

      expect(result, isNotNull);
      expect(result!.provider, equals('s3'));
      expect(result.isS3, isTrue);
      expect(result.objectKey,
          equals('lab_reports/$patientId/$bookingId/$fileName'));
      expect(fakeS3.uploadCallCount, equals(1));
      expect(fakeS3.lastUploadedPurpose, equals('lab_reports'));
      expect(fakeS3.lastUploadedParentId, equals('$patientId/$bookingId'));
      expect(fakeS3.lastUploadedFileName, equals(fileName));
      expect(fakeS3.lastUploadedBytes, equals(samplePdfBytes));
      expect(firebaseUploadCalled, isFalse);
    });

    test(
        'load with reportStorageProvider "s3" resolves presigned URL and downloads bytes',
        () async {
      const expectedKey = 'lab_reports/$patientId/$bookingId/uuid-123.pdf';
      const fakePresignedUrl =
          'https://s3.ap-south-1.amazonaws.com/doctornect/presigned-token-url';

      fakeS3.downloadUrlToReturn = fakePresignedUrl;

      var httpCallCount = 0;
      LabReportFileStore.httpClient = FakeHttpClient((request) async {
        httpCallCount++;
        expect(request.url.toString(), equals(fakePresignedUrl));
        return http.Response.bytes(samplePdfBytes, 200);
      });

      var legacyDownloadCalled = false;
      LabReportFileStore.mockDownloadFromUrl = (url) async {
        legacyDownloadCalled = true;
        return null;
      };

      final loaded = await LabReportFileStore.loadReport(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        storageKey: expectedKey,
        storageProvider: 's3',
      );

      expect(loaded, isNotNull);
      expect(loaded, equals(samplePdfBytes));
      expect(fakeS3.getDownloadUrlCallCount, equals(1));
      expect(fakeS3.lastRequestedKey, equals(expectedKey));
      expect(httpCallCount, equals(1));
      expect(legacyDownloadCalled, isFalse);
    });

    test(
        'load with legacy firebasestorage URL routes to legacy path without S3',
        () async {
      const legacyUrl =
          'https://firebasestorage.googleapis.com/v0/b/app/o/lab_reports%2Fp1%2Ffile.pdf?alt=media';

      var legacyCalled = false;
      LabReportFileStore.mockDownloadFromUrl = (url) async {
        legacyCalled = true;
        expect(url, equals(legacyUrl));
        return samplePdfBytes;
      };

      LabReportFileStore.httpClient = FakeHttpClient((request) async {
        fail('HTTP client should not be called for legacy Firebase download');
      });

      final loaded = await LabReportFileStore.loadReport(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        storageUrl: legacyUrl,
      );

      expect(loaded, isNotNull);
      expect(loaded, equals(samplePdfBytes));
      expect(legacyCalled, isTrue);
      expect(fakeS3.getDownloadUrlCallCount, equals(0));
    });

    test('report with no storageProvider still opens via legacy download',
        () async {
      const legacyUrl =
          'https://firebasestorage.googleapis.com/v0/b/app/o/p1_b1.pdf';

      var legacyCalled = false;
      LabReportFileStore.mockDownloadFromUrl = (url) async {
        legacyCalled = true;
        return samplePdfBytes;
      };

      final loaded = await LabReportFileStore.loadReport(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        storageUrl: legacyUrl,
        storageKey: null,
        storageProvider: null,
      );

      expect(loaded, isNotNull);
      expect(loaded, equals(samplePdfBytes));
      expect(legacyCalled, isTrue);
      expect(fakeS3.getDownloadUrlCallCount, equals(0));
    });

    test(
        'cache invalidation: replacing report with new storageKey does not serve old cached bytes',
        () async {
      final oldPdfBytes =
          Uint8List.fromList(utf8.encode('%PDF-1.4 OLD_REPORT_CONTENT_UUID_1'));
      final newPdfBytes =
          Uint8List.fromList(utf8.encode('%PDF-1.4 NEW_REPORT_CONTENT_UUID_2'));

      const oldKey = 'lab_reports/$patientId/$bookingId/uuid-1.pdf';
      const newKey = 'lab_reports/$patientId/$bookingId/uuid-2.pdf';

      // 1. Prime the cache with the old report
      await LabReportFileStore.cacheLocally(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        bytes: oldPdfBytes,
        storageKey: oldKey,
      );

      // Verify the old report is indeed in the cache
      final cachedOld = await LabReportFileStore.readCached(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        storageKey: oldKey,
      );
      expect(cachedOld, equals(oldPdfBytes));

      // 2. Set up HTTP mock to return the new report when fetching newKey
      fakeS3.downloadUrlToReturn =
          'https://s3.ap-south-1.amazonaws.com/doctornect/new-presigned-url';
      var httpCallCount = 0;
      LabReportFileStore.httpClient = FakeHttpClient((request) async {
        httpCallCount++;
        return http.Response.bytes(newPdfBytes, 200);
      });

      // 3. Load report specifying the NEW storageKey
      final loadedNew = await LabReportFileStore.loadReport(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        storageKey: newKey,
        storageProvider: 's3',
      );

      // 4. Must NOT return oldPdfBytes; must return newPdfBytes fetched from S3
      expect(loadedNew, isNotNull);
      expect(loadedNew, equals(newPdfBytes));
      expect(httpCallCount, equals(1));
      expect(fakeS3.lastRequestedKey, equals(newKey));
    });

    test(
        'deleteS3Report: deletes old S3 object via S3StorageService.deleteObject',
        () async {
      const oldKey = 'lab_reports/$patientId/$bookingId/old-uuid-to-delete.pdf';

      await LabReportFileStore.deleteS3Report(oldKey);

      expect(fakeS3.deleteCallCount, equals(1));
      expect(fakeS3.lastDeletedKey, equals(oldKey));
    });
  });
}
