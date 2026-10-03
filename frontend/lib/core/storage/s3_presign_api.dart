import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../security/app_check_service.dart';

/// Credentials returned by the server for direct-to-S3 uploads.
@immutable
class S3UploadCredentials {
  const S3UploadCredentials({
    required this.uploadUrl,
    required this.objectKey,
  });

  final String uploadUrl;
  final String objectKey;

  factory S3UploadCredentials.fromMap(Map<dynamic, dynamic> map) {
    final uploadUrl = map['uploadUrl'] as String?;
    final objectKey = map['objectKey'] as String?;
    if (uploadUrl == null || objectKey == null) {
      throw StateError(
          'Invalid server response: missing uploadUrl or objectKey.');
    }
    return S3UploadCredentials(
      uploadUrl: uploadUrl,
      objectKey: objectKey,
    );
  }
}

/// Download details for a presigned S3 object.
@immutable
class S3DownloadResult {
  const S3DownloadResult({
    required this.url,
    required this.expiresIn,
  });

  final String url;
  final int expiresIn;

  factory S3DownloadResult.fromMap(Map<dynamic, dynamic> map) {
    final url = map['url'] as String?;
    final expiresIn = (map['expiresIn'] as num?)?.toInt() ?? 600;
    if (url == null) {
      throw StateError('Invalid server response: missing url.');
    }
    return S3DownloadResult(url: url, expiresIn: expiresIn);
  }
}

/// Structured exception thrown for storage operations.
class StorageException implements Exception {
  const StorageException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => code != null
      ? 'StorageException($code): $message'
      : 'StorageException: $message';
}

/// Isolation boundary for all S3 presign Cloud Function endpoints.
///
/// If backend hosting changes in the future, only this class needs to be swapped.
/// All other services and screens interact exclusively through [S3StorageService] / [StorageService].
class S3PresignApi {
  S3PresignApi._();
  static final S3PresignApi instance = S3PresignApi._();

  static const String region = 'asia-south1';

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: region);

  /// Requests a presigned PUT upload URL and generated object key from the backend.
  Future<S3UploadCredentials> getUploadUrl({
    required String purpose,
    required String parentId,
    required String fileName,
    required String contentType,
    required int sizeBytes,
  }) async {
    await AppCheckService.ensureForCallable();

    try {
      final callable = _functions.httpsCallable('getS3UploadUrl');
      final response = await callable.call<Map<dynamic, dynamic>>({
        'purpose': purpose,
        'parentId': parentId,
        'fileName': fileName,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
      });

      final data = response.data;
      return S3UploadCredentials.fromMap(data);
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[S3PresignApi] getUploadUrl failed: ${e.code} - ${e.message}');
      }
      throw StorageException(
        e.message ?? 'Failed to get upload authorization.',
        code: e.code,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[S3PresignApi] getUploadUrl unexpected error: $e');
      }
      throw StorageException('Could not connect to storage backend.',
          code: 'network-error');
    }
  }

  /// Requests a short-lived presigned GET download URL for an object key.
  Future<S3DownloadResult> getDownloadUrl({
    required String objectKey,
  }) async {
    await AppCheckService.ensureForCallable();

    try {
      final callable = _functions.httpsCallable('getS3DownloadUrl');
      final response = await callable.call<Map<dynamic, dynamic>>({
        'objectKey': objectKey,
      });

      return S3DownloadResult.fromMap(response.data);
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[S3PresignApi] getDownloadUrl failed for key: ${e.code} - ${e.message}');
      }
      throw StorageException(
        e.message ?? 'Access to this file was denied or expired.',
        code: e.code,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[S3PresignApi] getDownloadUrl error: $e');
      }
      throw StorageException('Could not connect to storage backend.',
          code: 'network-error');
    }
  }

  /// Batch resolves download URLs for up to 20 media object keys (e.g. photos/banners).
  Future<Map<String, String>> getDownloadUrls({
    required List<String> objectKeys,
  }) async {
    if (objectKeys.isEmpty) return const {};
    await AppCheckService.ensureForCallable();

    try {
      final callable = _functions.httpsCallable('getS3DownloadUrls');
      final response = await callable.call<Map<dynamic, dynamic>>({
        'objectKeys': objectKeys,
      });

      final rawMap = response.data['urls'] as Map<dynamic, dynamic>? ?? {};
      return rawMap.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[S3PresignApi] getDownloadUrls failed: ${e.code} - ${e.message}');
      }
      throw StorageException(
        e.message ?? 'Failed to fetch media URLs.',
        code: e.code,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[S3PresignApi] getDownloadUrls error: $e');
      }
      return const {};
    }
  }

  /// Deletes an object from S3 after backend owner authorization.
  Future<bool> deleteObject({
    required String objectKey,
  }) async {
    await AppCheckService.ensureForCallable();

    try {
      final callable = _functions.httpsCallable('deleteS3Object');
      final response = await callable.call<Map<dynamic, dynamic>>({
        'objectKey': objectKey,
      });

      return response.data['success'] == true;
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[S3PresignApi] deleteObject failed: ${e.code} - ${e.message}');
      }
      throw StorageException(
        e.message ?? 'Could not delete file.',
        code: e.code,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[S3PresignApi] deleteObject error: $e');
      }
      return false;
    }
  }
}
