import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../security/file_encryption_service.dart';
import 'firebase_bootstrap.dart';

/// Uploads lab reports to Firebase Storage and caches them locally (encrypted) for preview.
abstract final class LabReportFileStore {
  static const maxFileBytes = 8 * 1024 * 1024;
  static const uploadTimeout = Duration(seconds: 45);
  static const downloadTimeout = Duration(seconds: 30);

  static final Map<String, Uint8List> _webBytes = {};

  static String _cacheKey(String patientId, String bookingId, String fileName) =>
      '$patientId/$bookingId/${_sanitizeFileName(fileName)}';

  static String _sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[^\w.\-]'), '_');

  static String storagePath(String patientId, String bookingId, String fileName) =>
      'lab_reports/$patientId/$bookingId/${_sanitizeFileName(fileName)}';

  static Future<String> _localDirPath(String patientId, String bookingId) async {
    final root = await getApplicationDocumentsDirectory();
    return '${root.path}/lab_reports/$patientId/$bookingId';
  }

  /// Use a readable report name derived from the test instead of the raw picker filename.
  static String reportFileNameFor({
    required String testName,
    required String originalFileName,
  }) {
    final lower = originalFileName.toLowerCase();
    final ext = lower.endsWith('.png')
        ? '.png'
        : lower.endsWith('.jpg') || lower.endsWith('.jpeg')
            ? '.jpg'
            : '.pdf';
    final slug = testName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    if (slug.isEmpty) return _sanitizeFileName(originalFileName);
    return '${slug}_Lab_Report$ext';
  }

  static bool isValidPdf(Uint8List bytes) {
    if (bytes.length < 5) return false;
    return String.fromCharCodes(bytes.sublist(0, 4)) == '%PDF';
  }

  static bool isValidImage(Uint8List bytes, String fileName) {
    if (bytes.length < 4) return false;
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    }
    return false;
  }

  static bool matchesDeclaredType(Uint8List bytes, String fileName) {
    if (isImageFile(fileName)) return isValidImage(bytes, fileName);
    return isValidPdf(bytes);
  }

  static String? mimeTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  static bool isImageFile(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg');
  }

  static Future<String?> uploadToStorage({
    required String patientId,
    required String bookingId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!FirebaseBootstrap.isReady || bytes.isEmpty || bytes.length > maxFileBytes) {
      return null;
    }

    final ref = FirebaseStorage.instance.ref(
      storagePath(patientId, bookingId, fileName),
    );
    await ref
        .putData(
          bytes,
          SettableMetadata(contentType: mimeTypeFor(fileName)),
        )
        .timeout(uploadTimeout);
    return await ref.getDownloadURL().timeout(const Duration(seconds: 15));
  }

  static Future<Uint8List?> downloadFromUrl(String storageUrl) async {
    if (!FirebaseBootstrap.isReady || storageUrl.trim().isEmpty) return null;
    try {
      final ref = FirebaseStorage.instance.refFromURL(storageUrl);
      return await ref
          .getData(maxFileBytes)
          .timeout(downloadTimeout, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  static Future<void> cacheLocally({
    required String patientId,
    required String bookingId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) return;

    await FileEncryptionService.ensureInitialized();

    if (kIsWeb) {
      _webBytes[_cacheKey(patientId, bookingId, fileName)] =
          await FileEncryptionService.encryptForMemoryCache(bytes);
      return;
    }

    try {
      final dir = await _localDirPath(patientId, bookingId);
      await FileEncryptionService.writeDiskFile(
        directoryPath: dir,
        sanitizedFileName: _sanitizeFileName(fileName),
        plain: bytes,
      );
    } catch (_) {}
  }

  static Future<Uint8List?> readCached({
    required String patientId,
    required String bookingId,
    required String fileName,
  }) async {
    await FileEncryptionService.ensureInitialized();

    if (kIsWeb) {
      return FileEncryptionService.decryptFromMemoryCache(
        _webBytes[_cacheKey(patientId, bookingId, fileName)],
      );
    }

    try {
      final dir = await _localDirPath(patientId, bookingId);
      return FileEncryptionService.readDiskFileWithLegacyMigration(
        directoryPath: dir,
        sanitizedFileName: _sanitizeFileName(fileName),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> downloadFromPath(String path) async {
    if (!FirebaseBootstrap.isReady) return null;
    try {
      final ref = FirebaseStorage.instance.ref(path);
      return await ref
          .getData(maxFileBytes)
          .timeout(downloadTimeout, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _tryLoadFromSources({
    required String patientId,
    required String bookingId,
    required String fileName,
    String? storageUrl,
  }) async {
    final cached = await readCached(
      patientId: patientId,
      bookingId: bookingId,
      fileName: fileName,
    );
    if (cached != null && cached.isNotEmpty) return cached;

    if (storageUrl != null && storageUrl.trim().isNotEmpty) {
      final fromUrl = await downloadFromUrl(storageUrl);
      if (fromUrl != null && fromUrl.isNotEmpty) return fromUrl;
    }

    return downloadFromPath(storagePath(patientId, bookingId, fileName));
  }

  static Future<Uint8List?> loadReport({
    required String patientId,
    required String bookingId,
    required String fileName,
    String? storageUrl,
    List<String> alternateBookingIds = const [],
  }) async {
    final bookingIds = <String>{
      bookingId,
      ...alternateBookingIds,
    }.where((id) => id.trim().isNotEmpty).toList();

    Uint8List? downloaded;
    for (var i = 0; i < bookingIds.length; i++) {
      final id = bookingIds[i];
      downloaded = await _tryLoadFromSources(
        patientId: patientId,
        bookingId: id,
        fileName: fileName,
        storageUrl: i == 0 ? storageUrl : null,
      );
      if (downloaded != null && downloaded.isNotEmpty) break;
    }

    if (downloaded != null &&
        downloaded.isNotEmpty &&
        !matchesDeclaredType(downloaded, fileName)) {
      return null;
    }

    if (downloaded != null && downloaded.isNotEmpty) {
      await cacheLocally(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        bytes: downloaded,
      );
    }
    return downloaded;
  }
}
