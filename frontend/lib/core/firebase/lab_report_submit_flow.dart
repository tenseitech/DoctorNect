import 'package:flutter/foundation.dart';

import '../storage/storage_service.dart';
import '../supabase/supabase_bootstrap.dart';
import 'lab_report_file_store.dart';

/// Shared S3 + Supabase ordering for lab report submission.
abstract final class LabReportSubmitFlow {
  static const String notReadyMessage =
      'Cannot submit report: server connection is not ready. Check your network and try again.';

  static const String persistFailedMessage =
      'Report file uploaded but the lab record could not be updated. Please try again.';

  @visibleForTesting
  static Future<void> Function(String objectKey)? debugDeleteS3ReportOverride;

  static void ensureSupabaseReady() {
    if (!SupabaseBootstrap.isReady) {
      throw StateError(notReadyMessage);
    }
  }

  /// After [uploadResult] is stored in S3: RPC must succeed, then local cache, then delete prior key.
  ///
  /// New S3 object deletion:
  /// - [persistToDatabase] returns `false` → delete new key, throw [persistFailedMessage].
  /// - [persistToDatabase] throws → call [confirmNewKeyPersistedAfterError]; if it returns true
  ///   (DB already references [newKey], e.g. RPC succeeded but response was lost), keep new key
  ///   and continue; if false, delete new key (best effort) and rethrow.
  /// After a successful persist, [cacheLocally] / old-key delete failures are logged only.
  static Future<void> finalizeAfterUpload({
    required StorageUploadResult uploadResult,
    required Future<bool> Function() persistToDatabase,
    required Future<void> Function() cacheLocally,
    String? existingReportStorageKey,
    Future<bool> Function(String newKey)? confirmNewKeyPersistedAfterError,
  }) async {
    final newKey = uploadResult.objectKey;

    var persisted = false;
    try {
      persisted = await persistToDatabase();
    } catch (e, st) {
      final recovered =
          await confirmNewKeyPersistedAfterError?.call(newKey) ?? false;
      if (recovered) {
        debugPrint(
          '[LabReportSubmitFlow] persistToDatabase threw but DB already references '
          '$newKey; keeping S3 object and continuing.',
        );
        persisted = true;
      } else {
        await _deleteS3ReportBestEffort(
          newKey,
          reason: 'persist threw and confirmNewKeyPersistedAfterError was false',
        );
        debugPrint(
          '[LabReportSubmitFlow] persistToDatabase threw and DB does not reference '
          '$newKey; new object removed (best effort).',
        );
        Error.throwWithStackTrace(e, st);
      }
    }

    if (!persisted) {
      await _deleteS3ReportBestEffort(
        newKey,
        reason: 'persistToDatabase returned false',
      );
      throw StateError(persistFailedMessage);
    }

    try {
      await cacheLocally();
    } catch (e, st) {
      debugPrint(
        '[LabReportSubmitFlow] cacheLocally failed after DB persist '
        '(new key retained: $newKey): $e\n$st',
      );
    }

    final oldKey = existingReportStorageKey?.trim();
    if (oldKey != null && oldKey.isNotEmpty && oldKey != newKey) {
      try {
        await _deleteS3Report(oldKey);
      } catch (e, st) {
        debugPrint(
          '[LabReportSubmitFlow] failed to delete old report key $oldKey '
          '(new key $newKey retained): $e\n$st',
        );
      }
    }
  }

  static Future<void> _deleteS3Report(String objectKey) async {
    final override = debugDeleteS3ReportOverride;
    if (override != null) {
      await override(objectKey);
      return;
    }
    await LabReportFileStore.deleteS3Report(objectKey);
  }

  static Future<void> _deleteS3ReportBestEffort(
    String objectKey, {
    required String reason,
  }) async {
    try {
      await _deleteS3Report(objectKey);
    } catch (e, st) {
      debugPrint(
        '[LabReportSubmitFlow] orphan cleanup failed ($reason, key=$objectKey): $e\n$st',
      );
    }
  }
}
