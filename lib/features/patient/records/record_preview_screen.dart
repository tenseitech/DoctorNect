import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_colors.dart';
import 'data/health_record_file_store.dart';
import 'models/health_record_models.dart';
import 'utils/record_type_style.dart';
import '../../../core/theme/app_typography.dart';

class RecordPreviewScreen extends StatefulWidget {
  const RecordPreviewScreen({
    super.key,
    required this.record,
    this.viewerPatientId,
  });

  final HealthRecord record;

  /// When a doctor views a patient's uploaded file.
  final String? viewerPatientId;

  @override
  State<RecordPreviewScreen> createState() => _RecordPreviewScreenState();
}

class _RecordPreviewScreenState extends State<RecordPreviewScreen> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    final record = widget.record;
    if (!record.hasUploadedFile) {
      setState(() {
        _loading = false;
        _error = 'No file attached to this record.';
      });
      return;
    }

    final patientId = widget.viewerPatientId ?? PatientSession.loggedInPatientId;
    if (patientId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Sign in to view this file.';
      });
      return;
    }

    try {
      final bytes = await HealthRecordFileStore.loadRecord(
        patientId: patientId,
        recordId: record.id,
        fileName: record.fileName,
        storageUrl: record.storageUrl,
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
        _error = bytes == null ? 'File not available on this device or in cloud storage.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open this file.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final style = RecordTypeStyle.forType(record.type);

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        title: Text(record.title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.headlineSmall)),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        actions: [
          if (_bytes != null)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              onPressed: () {
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(record, style)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: AppColors.surfaceOf(context),
            child: Text(
              '${DateFormat('dd MMM yyyy').format(record.date)} · ${record.fileName}',
              style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(HealthRecord record, RecordTypeStyle style) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.patientTeal),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 64, color: style.color),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
              ),
              if (record.fileStorage == HealthRecordFileStorage.local) ...[
                const SizedBox(height: 8),
                Text(
                  'Files may be stored on the device where they were uploaded, or in cloud storage when sync is enabled.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final bytes = _bytes!;
    if (record.isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: Center(
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      );
    }

    return PdfPreview(
      maxPageWidth: 700,
      allowPrinting: false,
      allowSharing: true,
      canChangeOrientation: false,
      canChangePageFormat: false,
      build: (_) async => bytes,
    );
  }
}
