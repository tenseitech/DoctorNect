import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/firebase/lab_report_file_store.dart';

/// Native / desktop: PDF via printing; images via share intent (includes Save).
Future<void> downloadLabReportBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  if (LabReportFileStore.isImageFile(fileName)) {
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
      text: fileName,
    );
    return;
  }

  await Printing.sharePdf(bytes: bytes, filename: fileName);
}
