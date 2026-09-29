import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 's3_presign_api.dart';
import 'storage_service.dart';

/// Concrete [StorageService] uploading/downloading files directly to/from AWS S3
/// via presigned URLs obtained from [S3PresignApi].
///
/// Contains NO direct dependency on Firebase Cloud Functions, allowing backend
/// endpoint swapping without changing this class.
class S3StorageService implements StorageService {
  S3StorageService({
    S3PresignApi? api,
    http.Client? httpClient,
  })  : _api = api ?? S3PresignApi.instance,
        _http = httpClient ?? http.Client();

  static S3StorageService _instance = S3StorageService();
  static S3StorageService get instance => _instance;
  @visibleForTesting
  static set instance(S3StorageService service) => _instance = service;

  final S3PresignApi _api;
  final http.Client _http;

  @override
  Future<StorageUploadResult> uploadBytes({
    required String purpose,
    required String parentId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    if (bytes.isEmpty) {
      throw const StorageException('Cannot upload an empty file.',
          code: 'empty-file');
    }

    final totalBytes = bytes.length;

    // 1. Request presigned PUT URL and generated key from backend
    final creds = await _api.getUploadUrl(
      purpose: purpose,
      parentId: parentId,
      fileName: fileName,
      contentType: contentType,
      sizeBytes: totalBytes,
    );

    onProgress?.call(0, totalBytes);

    // 2. Prepare headers (must match presigned URL signed headers)
    final headers = <String, String>{
      'content-type': contentType,
    };

    // On non-web platforms, set Content-Length explicitly to prevent chunked transfer.
    // On web, browsers forbid manually setting Content-Length and set it automatically.
    if (!kIsWeb) {
      headers['content-length'] = totalBytes.toString();
    }

    final uri = Uri.parse(creds.uploadUrl);

    try {
      // Direct raw byte PUT to S3
      final response = await _http.put(
        uri,
        headers: headers,
        body: bytes,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        onProgress?.call(totalBytes, totalBytes);
        return StorageUploadResult(
          objectKey: creds.objectKey,
          downloadUrl: null,
          provider: 's3',
        );
      }

      final bodyStr = response.body;
      if (response.statusCode == 403 &&
          bodyStr.contains('SignatureDoesNotMatch')) {
        throw const StorageException(
          'S3 upload signature mismatch: verify Content-Type and file size match exactly.',
          code: 'signature-does-not-match',
        );
      }

      throw StorageException(
        'S3 upload rejected (status ${response.statusCode}).',
        code: 's3-http-${response.statusCode}',
      );
    } on StorageException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[S3StorageService] HTTP upload error: $e');
      }
      throw StorageException('Network error while uploading to S3.',
          code: 'network-error');
    }
  }

  @override
  Future<String?> getDownloadUrl(String keyOrUrl) async {
    final trimmed = keyOrUrl.trim();
    if (trimmed.isEmpty) return null;

    // Legacy full URL pass-through (e.g. firebasestorage.googleapis.com)
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    try {
      final result = await _api.getDownloadUrl(objectKey: trimmed);
      return result.url;
    } on StorageException catch (_) {
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[S3StorageService] getDownloadUrl error: $e');
      }
      return null;
    }
  }

  @override
  Future<Map<String, String>> getDownloadUrls(List<String> keysOrUrls) async {
    if (keysOrUrls.isEmpty) return const {};

    final result = <String, String>{};
    final s3Keys = <String>[];

    for (final item in keysOrUrls) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        result[trimmed] = trimmed;
      } else {
        s3Keys.add(trimmed);
      }
    }

    if (s3Keys.isEmpty) return result;

    // Batch resolve in chunks of 20 (API cap)
    const chunkSize = 20;
    for (var i = 0; i < s3Keys.length; i += chunkSize) {
      final end =
          (i + chunkSize < s3Keys.length) ? i + chunkSize : s3Keys.length;
      final chunk = s3Keys.sublist(i, end);

      try {
        final resolved = await _api.getDownloadUrls(objectKeys: chunk);
        result.addAll(resolved);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[S3StorageService] getDownloadUrls chunk failed: $e');
        }
      }
    }

    return result;
  }

  @override
  Future<bool> deleteObject(String keyOrUrl) async {
    final trimmed = keyOrUrl.trim();
    if (trimmed.isEmpty) return false;

    // If it's a legacy URL, S3 service does not delete it
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return false;
    }

    try {
      return await _api.deleteObject(objectKey: trimmed);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[S3StorageService] deleteObject error: $e');
      }
      return false;
    }
  }
}
