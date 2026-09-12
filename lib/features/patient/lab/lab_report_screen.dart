import '../../../core/firebase/firestore_service.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/firebase/lab_report_file_store.dart';
import '../../../core/theme/app_colors.dart';
import 'lab_report_download_stub.dart'
    if (dart.library.html) 'lab_report_download_web.dart' as lab_report_download;
import 'lab_report_pdf_view_stub.dart'
    if (dart.library.html) 'lab_report_pdf_view_web.dart' as lab_report_pdf_view;
import 'package:medibond/features/shared/widgets/lab_page_layout.dart';

class LabReportScreen extends StatefulWidget {
  const LabReportScreen({
    super.key,
    this.booking,
    this.testName,
    this.bookingId,
    this.patientId,
    this.reportFileName,
    this.storageUrl,
  }) : assert(booking != null || (testName != null && bookingId != null));

  final LabBookingRecord? booking;
  final String? testName;
  final String? bookingId;

  /// Extra fields for doctor-ordered lab tests (where no LabBookingRecord exists).
  final String? patientId;
  final String? reportFileName;
  final String? storageUrl;

  String get displayTestName => booking?.testName ?? testName ?? 'Lab test';
  String get displayBookingId => booking?.bookingId ?? bookingId ?? '';

  @override
  State<LabReportScreen> createState() => _LabReportScreenState();
}

class _LabReportScreenState extends State<LabReportScreen> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    final booking = widget.booking;

    final String? patientId = booking?.patientId ?? widget.patientId;
    final String? bookingId = booking?.reportOwnerBookingId ?? widget.bookingId;
    final String? fileName = booking?.reportFileName ?? widget.reportFileName;
    final String? url = booking?.reportStorageUrl ?? widget.storageUrl;
    final alternateBookingIds = booking?.linkedBookingIds ?? const <String>[];

    if (patientId == null ||
        bookingId == null ||
        fileName == null ||
        fileName.isEmpty ||
        url == null ||
        url.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Report preview is not available yet.';
      });
      return;
    }

    try {
      final bytes = await LabReportFileStore.loadReport(
        patientId: patientId,
        bookingId: bookingId,
        fileName: fileName,
        storageUrl: url,
        alternateBookingIds: alternateBookingIds,
      ).timeout(
        LabReportFileStore.downloadTimeout,
        onTimeout: () => null,
      );

      if (!mounted) return;

      String? error;
      if (bytes == null || bytes.isEmpty) {
        error = 'Could not load the report. Check your connection and try again.';
      } else if (!LabReportFileStore.matchesDeclaredType(bytes, fileName)) {
        error =
            'The linked report file looks invalid or mismatched. Ask your lab to re-upload the correct report.';
      }

      setState(() {
        _bytes = error == null ? bytes : null;
        _loading = false;
        _error = error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open this report.';
      });
    }
  }

  String get _reportFileName =>
      widget.booking?.reportFileName ?? widget.reportFileName ?? '${widget.displayTestName}.pdf';

  Future<void> _shareReport() async {
    final bytes = _bytes;
    final fileName = _reportFileName;
    if (bytes == null) return;

    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          name: fileName,
          mimeType: LabReportFileStore.mimeTypeFor(fileName) ?? 'application/pdf',
        ),
      ],
      text: widget.displayTestName,
    );
  }

  Future<void> _downloadReport() async {
    final bytes = _bytes;
    final fileName = _reportFileName;
    if (bytes == null) return;

    await lab_report_download.downloadLabReportBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: LabReportFileStore.mimeTypeFor(fileName) ?? 'application/octet-stream',
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.booking?.reportFileName ?? widget.reportFileName;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: LabPageLayout.appBar(
        context,
        title: 'Lab Report',
        onBack: () => Navigator.pop(context),
        actions: [
          if (_bytes != null)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download',
              onPressed: _downloadReport,
            ),
          if (_bytes != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: _shareReport,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: AppColors.surfaceOf(context),
              child: _buildBody(fileName),
            ),
          ),
          if (fileName != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                border: Border(top: BorderSide(color: AppColors.borderOf(context))),
              ),
              child: Text(
                fileName,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(String? fileName) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.labPurple));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 64, color: AppColors.labPurple),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                    _bytes = null;
                  });
                  _loadReport();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final bytes = _bytes!;
    if (fileName != null && LabReportFileStore.isImageFile(fileName)) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
      );
    }

    return lab_report_pdf_view.LabReportPdfView(
      bytes: bytes,
      fileName: fileName ?? _reportFileName,
      onDownload: _downloadReport,
    );
  }
}
