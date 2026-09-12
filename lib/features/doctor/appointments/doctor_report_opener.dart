import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/patient_sharing_messages.dart';
import '../../patient/records/data/health_record_file_store.dart';
import '../../patient/records/models/health_record_models.dart';
import '../../patient/records/record_preview_screen.dart';

abstract final class DoctorReportOpener {
  static Future<void> open(
    BuildContext context, {
    required String reportName,
    String? patientId,
  }) async {
    if (patientId == null || patientId.isEmpty) {
      _showMessage(
        context,
        title: reportName,
        message: 'Patient record is not linked to this appointment.',
      );
      return;
    }

    try {
      if (!await FirestoreService.instance.patientProfile.isPatientSharingClinicalDataWithDoctors(
        patientId,
      )) {
        if (!context.mounted) return;
        _showMessage(
          context,
          title: reportName,
          message: PatientSharingMessages.dataNotSharedWithDoctors,
        );
        return;
      }

      final records =
          await FirestoreService.instance.patientProfile.fetchHealthRecordsForDoctor(patientId);
      final match = _findRecord(records, reportName);

      if (match != null && match.hasUploadedFile) {
        if (!context.mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => RecordPreviewScreen(
              record: match,
              viewerPatientId: patientId,
            ),
          ),
        );
        return;
      }

      // Fallback: report name may be the raw file name under any shared record folder.
      for (final record in records) {
        if (!record.hasUploadedFile) continue;
        final bytes = await HealthRecordFileStore.loadRecord(
          patientId: patientId,
          recordId: record.id,
          fileName: reportName,
          storageUrl: record.storageUrl,
        );
        if (bytes != null) {
          if (!context.mounted) return;
          final previewRecord = HealthRecord(
            id: record.id,
            title: reportName,
            type: record.type,
            date: record.date,
            source: record.source,
            fileName: reportName,
            doctorName: record.doctorName,
            labName: record.labName,
            isImage: reportName.toLowerCase().endsWith('.jpg') ||
                reportName.toLowerCase().endsWith('.jpeg') ||
                reportName.toLowerCase().endsWith('.png') ||
                reportName.toLowerCase().endsWith('.webp'),
            notes: record.notes,
            sharedWithDoctors: record.sharedWithDoctors,
            fileStorage: record.fileStorage,
            storageUrl: record.storageUrl,
          );
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => RecordPreviewScreen(
                record: previewRecord,
                viewerPatientId: patientId,
              ),
            ),
          );
          return;
        }
      }

      if (!context.mounted) return;
      _showMessage(
        context,
        title: reportName,
        message:
            'Report file is not available on this device. Ask the patient to upload and share it from the Records tab.',
      );
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(
        context,
        title: reportName,
        message: 'Could not open this report. Check internet and try again.',
      );
    }
  }

  static HealthRecord? _findRecord(List<HealthRecord> records, String reportName) {
    final normalized = reportName.trim().toLowerCase();
    for (final record in records) {
      final fileName = record.fileName.trim().toLowerCase();
      final title = record.title.trim().toLowerCase();
      if (fileName == normalized ||
          title == normalized ||
          fileName.contains(normalized) ||
          normalized.contains(fileName) ||
          title.contains(normalized)) {
        return record;
      }
    }
    return null;
  }

  static void _showMessage(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }
}
