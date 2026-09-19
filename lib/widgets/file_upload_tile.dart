import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants/app_constants.dart';
import '../core/security/input_sanitize.dart';
import '../core/theme/app_colors.dart';
import 'required_field_label.dart';
import '../core/theme/app_typography.dart';

class FileUploadTile extends StatelessWidget {
  const FileUploadTile({
    super.key,
    required this.label,
    required this.fileName,
    required this.onPick,
    this.accentColor = AppColors.doctorBlue,
    this.errorText,
    this.isRequired = false,
    this.isUploading = false,
  });

  final String label;
  final String? fileName;
  final VoidCallback onPick;
  final Color accentColor;
  final String? errorText;
  final bool isRequired;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    final hasFile = fileName != null && fileName!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RequiredFieldLabels.text(
          label,
          isRequired: isRequired,
          style: GoogleFonts.inter(
            fontSize: AppTypography.bodyMedium,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: isUploading ? null : onPick,
          borderRadius: BorderRadius.circular(AppConstants.inputRadius),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBgOf(context),
              borderRadius: BorderRadius.circular(AppConstants.inputRadius),
              border: Border.all(
                color: errorText != null
                    ? AppColors.error
                    : AppColors.borderOf(context),
              ),
            ),
            child: Row(
              children: [
                if (isUploading)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accentColor,
                    ),
                  )
                else
                  Icon(
                    hasFile
                        ? Icons.check_circle_outline
                        : Icons.cloud_upload_outlined,
                    color: hasFile
                        ? accentColor
                        : AppColors.textSecondaryOf(context),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isUploading
                        ? 'Uploading...'
                        : (hasFile ? fileName! : 'Tap to upload PDF file'),
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      color: hasFile
                          ? AppColors.textPrimaryOf(context)
                          : AppColors.textSecondaryOf(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: AppColors.textSecondaryOf(context)),
              ],
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium, color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

class PickedDocument {
  const PickedDocument({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

/// Opens the file picker restricted to PDF files only.
///
/// Bug fix: previously allowed jpg/jpeg/png alongside pdf. Certificates and
/// ID proofs must now be submitted strictly as PDF.
Future<String?> pickDocument() async {
  final doc = await pickDocumentData();
  return doc?.name;
}

/// Opens file picker restricted to PDF with byte retrieval enabled for Storage upload.
Future<PickedDocument?> pickDocumentData() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    withData: true,
  );
  if (result != null && result.files.isNotEmpty) {
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return null;
    final name = InputSanitize.fileName(file.name, fallback: 'document.pdf');
    if (!InputSanitize.isAllowedPdf(name)) return null;
    final sizeErr = InputSanitize.validateUploadBytes(
      byteLength: bytes.length,
      maxBytes: InputSanitize.maxPdfBytes,
      field: 'PDF',
    );
    if (sizeErr != null) return null;
    return PickedDocument(name: name, bytes: bytes);
  }
  return null;
}
