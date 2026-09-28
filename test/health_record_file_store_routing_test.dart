import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medibond/core/security/file_encryption_service.dart';
import 'package:medibond/core/storage/s3_storage_service.dart';
import 'package:medibond/core/storage/storage_feature_flag.dart';
import 'package:medibond/core/storage/storage_service.dart';
import 'package:medibond/features/patient/records/data/health_record_file_store.dart';

class FakeS3StorageService extends S3StorageService {
  int uploadCallCount = 0;
  int getDownloadUrlCallCount = 0;
  String? lastUploadedPurpose;
  String? lastUploadedParentId;
  String? lastUploadedFileName;
  Uint8List? lastUploadedBytes;
  String? lastRequestedKey;

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
          objectKey: 'health_records/$parentId/$fileName',
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

    tempDir = Directory.systemTemp.createTempSync('health_record_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    StorageFeatureFlag.debugOverride = null;
    HealthRecordFileStore.httpClient = null;
    HealthRecordFileStore.mockDownloadFromUrl = null;
    HealthRecordFileStore.mockFirebaseUpload = null;
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
    HealthRecordFileStore.httpClient = null;
    HealthRecordFileStore.mockDownloadFromUrl = null;
    HealthRecordFileStore.mockFirebaseUpload = null;
  });

  group('HealthRecordFileStore Routing & Feature Flag', () {
    const patientId = 'p_test_123';
    const recordId = 'hr_test_456';
    const fileName = 'blood_test.pdf';
    final sampleBytes = Uint8List.fromList(utf8.encode('PDF_MOCK_DATA_CONTENT'));

    test('flag OFF: uploads to Firebase Storage, S3 is NOT called', () async {
      StorageFeatureFlag.debugOverride = false;

      var firebaseUploadCalled = false;
      HealthRecordFileStore.mockFirebaseUpload =
          (pId, rId, fName, bytes) async {
        firebaseUploadCalled = true;
        expect(pId, equals(patientId));
        expect(rId, equals(recordId));
        expect(fName, equals(fileName));
        expect(bytes, equals(sampleBytes));
        return 'https://firebasestorage.googleapis.com/v0/b/test/o/health_records.pdf';
      };

      final result = await HealthRecordFileStore.uploadRecord(
        patientId: patientId,
        recordId: recordId,
        fileName: fileName,
        bytes: sampleBytes,
      );

      expect(result, isNotNull);
      expect(result!.provider, equals('firebase'));
      expect(result.downloadUrl, contains('firebasestorage.googleapis.com'));
      expect(firebaseUploadCalled, isTrue);
      expect(fakeS3.uploadCallCount, equals(0));
    });

    test('flag ON: uploads via S3StorageService, Firebase upload is NOT called', () async {
      StorageFeatureFlag.debugOverride = true;

      var firebaseUploadCalled = false;
      HealthRecordFileStore.mockFirebaseUpload =
          (pId, rId, fName, bytes) async {
        firebaseUploadCalled = true;
        return 'https://firebasestorage.googleapis.com/unexpected';
      };

      final result = await HealthRecordFileStore.uploadRecord(
        patientId: patientId,
        recordId: recordId,
        fileName: fileName,
        bytes: sampleBytes,
      );

      expect(result, isNotNull);
      expect(result!.provider, equals('s3'));
      expect(result.isS3, isTrue);
      expect(result.objectKey, equals('health_records/$patientId/$recordId/$fileName'));
      expect(fakeS3.uploadCallCount, equals(1));
      expect(fakeS3.lastUploadedPurpose, equals('health_records'));
      expect(fakeS3.lastUploadedParentId, equals('$patientId/$recordId'));
      expect(fakeS3.lastUploadedFileName, equals(fileName));
      expect(fakeS3.lastUploadedBytes, equals(sampleBytes));
      expect(firebaseUploadCalled, isFalse);
    });

    test('load with storageProvider "s3" resolves presigned URL and downloads bytes', () async {
      final expectedContent = utf8.encode('S3_PRESIGNED_DOWNLOAD_BODY');
      const expectedKey = 'health_records/$patientId/$recordId/uuid-123.pdf';
      const fakePresignedUrl = 'https://s3.ap-south-1.amazonaws.com/doctornect/presigned-token-url';

      fakeS3.downloadUrlToReturn = fakePresignedUrl;

      var httpCallCount = 0;
      HealthRecordFileStore.httpClient = FakeHttpClient((request) async {
        httpCallCount++;
        expect(request.url.toString(), equals(fakePresignedUrl));
        return http.Response.bytes(expectedContent, 200);
      });

      var legacyDownloadCalled = false;
      HealthRecordFileStore.mockDownloadFromUrl = (url) async {
        legacyDownloadCalled = true;
        return null;
      };

      final loaded = await HealthRecordFileStore.loadRecord(
        patientId: patientId,
        recordId: recordId,
        fileName: fileName,
        storageKey: expectedKey,
        storageProvider: 's3',
      );

      expect(loaded, isNotNull);
      expect(loaded, equals(expectedContent));
      expect(fakeS3.getDownloadUrlCallCount, equals(1));
      expect(fakeS3.lastRequestedKey, equals(expectedKey));
      expect(httpCallCount, equals(1));
      expect(legacyDownloadCalled, isFalse);
    });

    test('load with legacy firebasestorage URL routes to legacy path without S3', () async {
      final legacyContent = utf8.encode('FIREBASE_LEGACY_BYTES');
      const legacyUrl = 'https://firebasestorage.googleapis.com/v0/b/app/o/health_records%2Fp1%2Ffile.pdf?alt=media';

      var legacyCalled = false;
      HealthRecordFileStore.mockDownloadFromUrl = (url) async {
        legacyCalled = true;
        expect(url, equals(legacyUrl));
        return Uint8List.fromList(legacyContent);
      };

      HealthRecordFileStore.httpClient = FakeHttpClient((request) async {
        fail('HTTP client should not be called for legacy Firebase download');
      });

      final loaded = await HealthRecordFileStore.loadRecord(
        patientId: patientId,
        recordId: recordId,
        fileName: fileName,
        storageUrl: legacyUrl,
      );

      expect(loaded, isNotNull);
      expect(loaded, equals(legacyContent));
      expect(legacyCalled, isTrue);
      expect(fakeS3.getDownloadUrlCallCount, equals(0));
    });

    test('record with no storageProvider still opens via legacy download', () async {
      final content = utf8.encode('UNTAGGED_PROVIDER_CONTENT');
      const legacyUrl = 'https://firebasestorage.googleapis.com/v0/b/app/o/p1_r1.pdf';

      var legacyCalled = false;
      HealthRecordFileStore.mockDownloadFromUrl = (url) async {
        legacyCalled = true;
        return Uint8List.fromList(content);
      };

      final loaded = await HealthRecordFileStore.loadRecord(
        patientId: patientId,
        recordId: recordId,
        fileName: fileName,
        storageUrl: legacyUrl,
        storageKey: null,
        storageProvider: null,
      );

      expect(loaded, isNotNull);
      expect(loaded, equals(content));
      expect(legacyCalled, isTrue);
      expect(fakeS3.getDownloadUrlCallCount, equals(0));
    });
  });
}
