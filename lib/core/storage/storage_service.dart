import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Result of a completed storage upload.
@immutable
class StorageUploadResult {
  const StorageUploadResult({
    required this.objectKey,
    this.downloadUrl,
    required this.provider,
  });

  /// The canonical object identifier (e.g. `health_records/p1/hr1/uuid.pdf`).
  /// Stored in database records for S3.
  final String objectKey;

  /// Optional direct URL (used primarily for legacy Firebase Storage or pre-resolved URLs).
  final String? downloadUrl;

  /// Provider identifier: 's3' or 'firebase'.
  final String provider;

  bool get isS3 => provider == 's3';
}

/// Abstract contract for storage operations across the application.
abstract class StorageService {
  /// Uploads raw bytes directly to storage.
  Future<StorageUploadResult> uploadBytes({
    required String purpose,
    required String parentId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
    void Function(int sentBytes, int totalBytes)? onProgress,
  });

  /// Resolves a short-lived download URL for an object key (or returns the URL if legacy).
  Future<String?> getDownloadUrl(String keyOrUrl);

  /// Resolves batch download URLs for multiple object keys.
  Future<Map<String, String>> getDownloadUrls(List<String> keysOrUrls);

  /// Deletes an object from storage.
  Future<bool> deleteObject(String keyOrUrl);
}
