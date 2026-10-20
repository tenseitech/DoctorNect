import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medibond/core/storage/s3_presign_api.dart';
import 'package:medibond/core/storage/s3_storage_service.dart';

class MockS3PresignApi extends S3PresignApi {
  MockS3PresignApi() : super.testable();

  int getUploadUrlCalls = 0;
  int confirmUploadCalls = 0;

  String? lastConfirmedKey;
  String? lastConfirmedPurpose;
  String? lastConfirmedRecordId;

  S3UploadCredentials credentialsToReturn = const S3UploadCredentials(
    uploadUrl: 'https://doctornect.s3.ap-south-1.amazonaws.com/test-url',
    objectKey: 'health_records/p1/rec1/uuid123.pdf',
  );

  @override
  Future<S3UploadCredentials> getUploadUrl({
    required String purpose,
    required String parentId,
    required String fileName,
    required String contentType,
    required int sizeBytes,
  }) async {
    getUploadUrlCalls++;
    return credentialsToReturn;
  }

  @override
  Future<Map<String, dynamic>> confirmUpload({
    required String objectKey,
    required String purpose,
    String? recordId,
  }) async {
    confirmUploadCalls++;
    lastConfirmedKey = objectKey;
    lastConfirmedPurpose = purpose;
    lastConfirmedRecordId = recordId;
    return {
      'success': true,
      'objectKey': objectKey,
      'contentLength': 1024,
    };
  }
}

class MockHttpClient extends http.BaseClient {
  MockHttpClient(this._handler);
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
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

  group('S3StorageService Confirmation Contract', () {
    test('uploadBytes invokes S3 PUT and automatically confirms with backend', () async {
      final mockApi = MockS3PresignApi();
      http.Request? capturedRequest;

      final mockHttp = MockHttpClient((request) async {
        capturedRequest = request as http.Request;
        return http.Response('', 200);
      });

      final service = S3StorageService(
        api: mockApi,
        httpClient: mockHttp,
      );

      final bytes = Uint8List.fromList(utf8.encode('PDF content bytes'));
      final result = await service.uploadBytes(
        purpose: 'health_records',
        parentId: 'p1/rec1',
        fileName: 'report.pdf',
        contentType: 'application/pdf',
        bytes: bytes,
      );

      // Verify S3 upload result
      expect(result.objectKey, 'health_records/p1/rec1/uuid123.pdf');
      expect(result.provider, 's3');
      expect(mockApi.getUploadUrlCalls, 1);

      // Verify HTTP request headers
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.method, 'PUT');
      expect(capturedRequest!.headers['content-type'], 'application/pdf');

      // Verify backend confirmation was called
      expect(mockApi.confirmUploadCalls, 1);
      expect(mockApi.lastConfirmedKey, 'health_records/p1/rec1/uuid123.pdf');
      expect(mockApi.lastConfirmedPurpose, 'health_records');
      expect(mockApi.lastConfirmedRecordId, 'p1/rec1');
    });

    test('uploadBytes throws and skips confirmUpload when HTTP PUT fails with 403', () async {
      final mockApi = MockS3PresignApi();
      final mockHttp = MockHttpClient((request) async {
        return http.Response(
          '<Error><Code>SignatureDoesNotMatch</Code></Error>',
          403,
        );
      });

      final service = S3StorageService(
        api: mockApi,
        httpClient: mockHttp,
      );

      final bytes = Uint8List.fromList(utf8.encode('PDF data'));
      expect(
        () => service.uploadBytes(
          purpose: 'health_records',
          parentId: 'p1/rec1',
          fileName: 'report.pdf',
          contentType: 'application/pdf',
          bytes: bytes,
        ),
        throwsA(isA<StorageException>().having(
          (e) => e.code,
          'code',
          'signature-does-not-match',
        )),
      );

      // Confirm upload should NOT be called if PUT fails
      expect(mockApi.confirmUploadCalls, 0);
    });

    test('explicit confirmUpload delegates to S3PresignApi', () async {
      final mockApi = MockS3PresignApi();
      final service = S3StorageService(
        api: mockApi,
        httpClient: MockHttpClient((req) async => http.Response('', 200)),
      );

      final res = await service.confirmUpload(
        objectKey: 'health_records/p1/rec1/doc.pdf',
        purpose: 'health_records',
        recordId: 'rec1',
      );

      expect(res['success'], true);
      expect(mockApi.confirmUploadCalls, 1);
      expect(mockApi.lastConfirmedKey, 'health_records/p1/rec1/doc.pdf');
    });
  });
}
