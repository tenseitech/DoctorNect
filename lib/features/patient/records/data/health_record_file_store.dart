import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/firebase/firebase_bootstrap.dart';
import '../../../../core/security/file_encryption_service.dart';

/// Persists health-record files locally (encrypted) and syncs to Firebase Storage when available.
abstract final class HealthRecordFileStore {
  static const maxFileBytes = 10 * 1024 * 1024;
  static const uploadTimeout = Duration(seconds: 45);
  static const downloadTimeout = Duration(seconds: 30);

  static final Map<String, Uint8List> _webBytes = {};

  static String _cacheKey(String patientId, String recordId, String fileName) =>
      '$patientId/$recordId/$fileName';

  static String _sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[^\w.\-]'), '_');

  static String storagePath(String patientId, String recordId, String fileName) =>
      'health_records/$patientId/$recordId/${_sanitizeFileName(fileName)}';

  static String? mimeTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  static Future<Directory> _baseDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/health_records');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static Future<String> recordDirPath(String patientId, String recordId) async {
    final base = await _baseDir();
    return '${base.path}/$patientId/$recordId';
  }

  static Future<File?> resolveFile({
    required String patientId,
    required String recordId,
    required String fileName,
  }) async {
    if (kIsWeb) return null;
    final dirPath = await recordDirPath(patientId, recordId);
    final sanitized = _sanitizeFileName(fileName);
    final encFile = File(
      '$dirPath/${FileEncryptionService.encryptedFileName(sanitized)}',
    );
    if (encFile.existsSync()) return encFile;

    final legacy = File('$dirPath/$sanitized');
    return legacy.existsSync() ? legacy : null;
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

  static Future<Uint8List?> readBytes({
    required String patientId,
    required String recordId,
    required String fileName,
    String? storageUrl,
  }) async {
    return loadRecord(
      patientId: patientId,
      recordId: recordId,
      fileName: fileName,
      storageUrl: storageUrl,
    );
  }

  /// Local encrypted cache first, then [storageUrl], then canonical Storage path.
  static Future<Uint8List?> loadRecord({
    required String patientId,
    required String recordId,
    required String fileName,
    String? storageUrl,
  }) async {
    await FileEncryptionService.ensureInitialized();

    if (kIsWeb) {
      final cached = await FileEncryptionService.decryptFromMemoryCache(
        _webBytes[_cacheKey(patientId, recordId, fileName)],
      );
      if (cached != null && cached.isNotEmpty) return cached;

      if (storageUrl != null && storageUrl.trim().isNotEmpty) {
        final fromUrl = await downloadFromUrl(storageUrl);
        if (fromUrl != null && fromUrl.isNotEmpty) {
          _webBytes[_cacheKey(patientId, recordId, fileName)] =
              await FileEncryptionService.encryptForMemoryCache(fromUrl);
          return fromUrl;
        }
      }

      final fromPath = await downloadFromPath(storagePath(patientId, recordId, fileName));
      if (fromPath != null && fromPath.isNotEmpty) {
        _webBytes[_cacheKey(patientId, recordId, fileName)] =
            await FileEncryptionService.encryptForMemoryCache(fromPath);
      }
      return fromPath;
    }

    final dirPath = await recordDirPath(patientId, recordId);
    final local = await FileEncryptionService.readDiskFileWithLegacyMigration(
      directoryPath: dirPath,
      sanitizedFileName: _sanitizeFileName(fileName),
    );
    if (local != null && local.isNotEmpty) return local;

    if (storageUrl != null && storageUrl.trim().isNotEmpty) {
      final fromUrl = await downloadFromUrl(storageUrl);
      if (fromUrl != null && fromUrl.isNotEmpty) {
        await saveFile(
          patientId: patientId,
          recordId: recordId,
          fileName: fileName,
          bytes: fromUrl,
        );
        return fromUrl;
      }
    }

    final fromPath = await downloadFromPath(storagePath(patientId, recordId, fileName));
    if (fromPath != null && fromPath.isNotEmpty) {
      await saveFile(
        patientId: patientId,
        recordId: recordId,
        fileName: fileName,
        bytes: fromPath,
      );
    }
    return fromPath;
  }

  static Future<bool> saveFile({
    required String patientId,
    required String recordId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty || bytes.length > maxFileBytes) return false;

    await FileEncryptionService.ensureInitialized();

    if (kIsWeb) {
      _webBytes[_cacheKey(patientId, recordId, fileName)] =
          await FileEncryptionService.encryptForMemoryCache(bytes);
      return true;
    }

    final dirPath = await recordDirPath(patientId, recordId);
    return FileEncryptionService.writeDiskFile(
      directoryPath: dirPath,
      sanitizedFileName: _sanitizeFileName(fileName),
      plain: bytes,
    );
  }

  static Future<String?> uploadToFirebaseStorage({
    required String patientId,
    required String recordId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!FirebaseBootstrap.isReady || bytes.isEmpty || bytes.length > maxFileBytes) {
      return null;
    }

    try {
      final ref = FirebaseStorage.instance.ref(
        storagePath(patientId, recordId, fileName),
      );
      await ref
          .putData(
            bytes,
            SettableMetadata(contentType: mimeTypeFor(fileName)),
          )
          .timeout(uploadTimeout);
      return await ref.getDownloadURL().timeout(const Duration(seconds: 15));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('HealthRecordFileStore.uploadToFirebaseStorage failed: $e\n$st');
      }
      return null;
    }
  }

  static Future<void> deleteFromStorage({
    required String patientId,
    required String recordId,
    required String fileName,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      await FirebaseStorage.instance
          .ref(storagePath(patientId, recordId, fileName))
          .delete();
    } catch (_) {
      // File may never have been uploaded.
    }
  }

  static Future<void> deleteRecordFiles({
    required String patientId,
    required String recordId,
    String? fileName,
  }) async {
    if (fileName != null) {
      await deleteFromStorage(
        patientId: patientId,
        recordId: recordId,
        fileName: fileName,
      );
    }

    if (kIsWeb) {
      if (fileName != null) {
        _webBytes.remove(_cacheKey(patientId, recordId, fileName));
      } else {
        final prefix = '$patientId/$recordId/';
        _webBytes.removeWhere((key, _) => key.startsWith(prefix));
      }
      return;
    }

    if (fileName != null) {
      final dirPath = await recordDirPath(patientId, recordId);
      await FileEncryptionService.deleteDiskFiles(
        directoryPath: dirPath,
        sanitizedFileName: _sanitizeFileName(fileName),
      );
      return;
    }

    final dir = Directory(await recordDirPath(patientId, recordId));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<void> deleteAllForPatient(String patientId) async {
    if (kIsWeb) {
      _webBytes.removeWhere((key, _) => key.startsWith('$patientId/'));
      return;
    }

    final base = await _baseDir();
    final dir = Directory('${base.path}/$patientId');
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}
