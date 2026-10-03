import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Mobile / desktop PDF preview via the printing package.
class LabReportPdfView extends StatelessWidget {
  const LabReportPdfView({
    super.key,
    required this.bytes,
    this.fileName,
    this.onDownload,
  });

  final Uint8List bytes;
  final String? fileName;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return PdfPreview(
      maxPageWidth: 700,
      allowPrinting: false,
      allowSharing: false,
      canChangeOrientation: false,
      canChangePageFormat: false,
      build: (_) async => bytes,
    );
  }
}
