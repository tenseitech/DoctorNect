import '../storage/storage_service.dart';
import '../supabase/supabase_bootstrap.dart';
import 'lab_report_file_store.dart';

/// Shared S3 + Supabase ordering for lab report submission.
abstract final class LabReportSubmitFlow {
  static const String notReadyMessage =
      'Cannot submit report: server connection is not ready. Check your network and try again.';

  static const String persistFailedMessage =
      'Report file uploaded but the lab record could not be updated. Please try again.';

  static void ensureSupabaseReady() {
    if (!SupabaseBootstrap.isReady) {
      throw StateError(notReadyMessage);
    }
  }

  /// After [uploadResult] is stored in S3: RPC must succeed, then local cache, then delete prior key.
  static Future<void> finalizeAfterUpload({
    required StorageUploadResult uploadResult,
    required Future<bool> Function() persistToDatabase,
    required Future<void> Function() cacheLocally,
    String? existingReportStorageKey,
  }) async {
    final newKey = uploadResult.objectKey;
    try {
      final persisted = await persistToDatabase();
      if (!persisted) {
        await LabReportFileStore.deleteS3Report(newKey);
        throw StateError(persistFailedMessage);
      }
      await cacheLocally();
      final oldKey = existingReportStorageKey?.trim();
      if (oldKey != null &&
          oldKey.isNotEmpty &&
          oldKey != newKey) {
        await LabReportFileStore.deleteS3Report(oldKey);
      }
    } on StateError catch (e) {
      if (e.message == persistFailedMessage) rethrow;
      await LabReportFileStore.deleteS3Report(newKey);
      rethrow;
    } catch (e) {
      await LabReportFileStore.deleteS3Report(newKey);
      rethrow;
    }
  }
}
