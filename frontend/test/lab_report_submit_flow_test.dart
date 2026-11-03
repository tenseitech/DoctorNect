import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/firebase/lab_report_submit_flow.dart';
import 'package:medibond/core/storage/storage_service.dart';

void main() {
  group('LabReportSubmitFlow.finalizeAfterUpload', () {
    tearDown(() {
      LabReportSubmitFlow.debugDeleteS3ReportOverride = null;
    });

    test('persist throw with DB already on newKey keeps new key and completes',
        () async {
      final deleted = <String>[];
      LabReportSubmitFlow.debugDeleteS3ReportOverride = (key) async {
        deleted.add(key);
      };

      await LabReportSubmitFlow.finalizeAfterUpload(
        uploadResult: const StorageUploadResult(
          objectKey: 'lab_reports/p/b/new.pdf',
          provider: 's3',
        ),
        existingReportStorageKey: 'lab_reports/p/b/old.pdf',
        persistToDatabase: () async {
          throw StateError('network timeout reading RPC response');
        },
        confirmNewKeyPersistedAfterError: (_) async => true,
        cacheLocally: () async {},
      );

      expect(deleted, ['lab_reports/p/b/old.pdf']);
    });

    test('persist throw with DB not on newKey deletes new key and rethrows',
        () async {
      final deleted = <String>[];
      LabReportSubmitFlow.debugDeleteS3ReportOverride = (key) async {
        deleted.add(key);
      };

      await expectLater(
        LabReportSubmitFlow.finalizeAfterUpload(
          uploadResult: const StorageUploadResult(
            objectKey: 'lab_reports/p/b/new.pdf',
            provider: 's3',
          ),
          persistToDatabase: () async {
            throw StateError('connection reset');
          },
          confirmNewKeyPersistedAfterError: (_) async => false,
          cacheLocally: () async {},
        ),
        throwsA(isA<StateError>()),
      );

      expect(deleted, ['lab_reports/p/b/new.pdf']);
    });

    test('persist false deletes new key only', () async {
      final deleted = <String>[];
      LabReportSubmitFlow.debugDeleteS3ReportOverride = (key) async {
        deleted.add(key);
      };

      await expectLater(
        LabReportSubmitFlow.finalizeAfterUpload(
          uploadResult: const StorageUploadResult(
            objectKey: 'lab_reports/p/b/new.pdf',
            provider: 's3',
          ),
          existingReportStorageKey: 'lab_reports/p/b/old.pdf',
          persistToDatabase: () async => false,
          cacheLocally: () async {},
        ),
        throwsA(isA<StateError>()),
      );

      expect(deleted, ['lab_reports/p/b/new.pdf']);
    });

    test('after RPC success, cacheLocally failure retains new key and completes',
        () async {
      final deleted = <String>[];
      LabReportSubmitFlow.debugDeleteS3ReportOverride = (key) async {
        deleted.add(key);
      };

      await LabReportSubmitFlow.finalizeAfterUpload(
        uploadResult: const StorageUploadResult(
          objectKey: 'lab_reports/p/b/new.pdf',
          provider: 's3',
        ),
        existingReportStorageKey: 'lab_reports/p/b/old.pdf',
        persistToDatabase: () async => true,
        cacheLocally: () async {
          throw StateError('disk full');
        },
      );

      expect(deleted, ['lab_reports/p/b/old.pdf']);
    });

    test('after RPC success, old key delete failure retains new key and completes',
        () async {
      final deleted = <String>[];
      LabReportSubmitFlow.debugDeleteS3ReportOverride = (key) async {
        if (key.contains('old.pdf')) {
          throw StateError('s3 delete denied');
        }
        deleted.add(key);
      };

      await LabReportSubmitFlow.finalizeAfterUpload(
        uploadResult: const StorageUploadResult(
          objectKey: 'lab_reports/p/b/new.pdf',
          provider: 's3',
        ),
        existingReportStorageKey: 'lab_reports/p/b/old.pdf',
        persistToDatabase: () async => true,
        cacheLocally: () async {},
      );

      expect(deleted, isEmpty);
    });
  });
}
