import 'package:flutter/foundation.dart';

import '../storage/storage_service.dart';
import '../supabase/supabase_bootstrap.dart';
import 'lab_report_file_store.dart';
import 'lab_report_persist_verify.dart';

/// Shared S3 + Supabase ordering for lab report submission.
abstract final class LabReportSubmitFlow {
  static const String notReadyMessage =
      'Cannot submit report: server connection is not ready. Check your network and try again.';

  static const String persistFailedMessage =
      'Report file uploaded but the lab record could not be updated. Please try again.';

  static const String partialPersistMessage =
      'Report file uploaded but only some lab records were updated. Please contact support or retry.';

  @visibleForTesting
  static Future<void> Function(String objectKey)? debugDeleteS3ReportOverride;

  static void ensureSupabaseReady() {
    if (!SupabaseBootstrap.isReady) {
      throw StateError(notReadyMessage);
    }
  }

  static Future<void> finalizeAfterUpload({
    required StorageUploadResult uploadResult,
    required Future<bool> Function() persistToDatabase,
    required Future<void> Function() cacheLocally,
    String? existingReportStorageKey,
    Future<LabReportKeyCheckResult> Function(String newKey)?
        confirmNewKeyPersistedAfterError,
  }) async {
    final newKey = uploadResult.objectKey;

    var persisted = false;
    try {
      persisted = await persistToDatabase();
    } catch (e, st) {
      final check = await _safeConfirmNewKey(confirmNewKeyPersistedAfterError, newKey);
      switch (check) {
        case LabReportKeyCheckResult.allRowsMatch:
          debugPrint(
            '[LabReportSubmitFlow] persistToDatabase threw but DB references '
            '$newKey; keeping S3 object and continuing.',
          );
          persisted = true;
        case LabReportKeyCheckResult.noRowsMatch:
          await _deleteS3ReportBestEffort(
            newKey,
            reason: 'persist threw and DB does not reference newKey',
          );
          Error.throwWithStackTrace(e, st);
        case LabReportKeyCheckResult.partialMatch:
          debugPrint(
            '[LabReportSubmitFlow] partial persist after throw: some rows reference '
            '$newKey, others do not; retaining S3 object.',
          );
          throw StateError(partialPersistMessage);
        case LabReportKeyCheckResult.inconclusive:
          debugPrint(
            '[LabReportSubmitFlow] persistToDatabase threw and DB re-read was '
            'inconclusive; retaining S3 object ($newKey).',
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

  static Future<LabReportKeyCheckResult> _safeConfirmNewKey(
    Future<LabReportKeyCheckResult> Function(String newKey)? confirm,
    String newKey,
  ) async {
    if (confirm == null) return LabReportKeyCheckResult.inconclusive;
    try {
      return await confirm(newKey);
    } catch (e, st) {
      debugPrint(
        '[LabReportSubmitFlow] confirmNewKeyPersistedAfterError failed '
        '(retaining $newKey): $e\n$st',
      );
      return LabReportKeyCheckResult.inconclusive;
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
