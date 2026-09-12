import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/media/gallery_image_picker.dart';

import '../../../core/firebase/lab_report_file_store.dart';
import '../../../core/firebase/models/doctor_lab_order.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/overflow_safe_layout.dart';
import '../data/lab_worklist_store.dart';

abstract final class LabReportUploadSheet {
  static Future<bool?> show(
    BuildContext context, {
    LabBookingRecord? booking,
    DoctorLabOrder? order,
  }) {
    assert(booking != null || order != null);
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _LabReportUploadSheet(booking: booking, order: order),
    );
  }
}

class _LabReportUploadSheet extends StatefulWidget {
  const _LabReportUploadSheet({this.booking, this.order});

  final LabBookingRecord? booking;
  final DoctorLabOrder? order;

  @override
  State<_LabReportUploadSheet> createState() => _LabReportUploadSheetState();
}

class _LabReportUploadSheetState extends State<_LabReportUploadSheet> {
  /// Soft warning threshold — typical lab PDFs are well under 1 MB.
  static const _largeFileWarningBytes = 2 * 1024 * 1024;

  PlatformFile? _file;
  bool _submitting = false;

  String get _patientName => widget.booking?.patientName ?? widget.order?.patientName ?? 'Patient';

  String get _testNames =>
      widget.booking?.testName ?? widget.order?.testNames.join(', ') ?? 'Lab test';

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<bool> _confirmSubmit(PlatformFile file) async {
    final sizeLabel = _formatFileSize(file.size);
    final isLarge = file.size >= _largeFileWarningBytes;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Confirm send report', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: scrollableDialogContent(
          context: dialogContext,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "You're about to send ${file.name} ($sizeLabel) to $_patientName for $_testNames.",
                style: GoogleFonts.inter(height: 1.45),
              ),
              if (isLarge) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDBA74)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFEA580C)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This file is larger than typical lab reports — please confirm this is the correct report.',
                          style: GoogleFonts.inter(fontSize: 13, color: Color(0xFF9A3412), height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.labPurple),
            child: const Text('Confirm send'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _pickFile() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photo'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Choose PDF'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'image') {
      final picked = await GalleryImagePicker.pickSingle();
      if (picked == null || !mounted) return;
      if (picked.bytes.length > LabReportFileStore.maxFileBytes) {
        AppToast.info(context, 'File exceeds 8 MB limit');
        return;
      }
      setState(() {
        _file = PlatformFile(
          name: picked.name,
          size: picked.bytes.length,
          bytes: picked.bytes,
          path: picked.path,
        );
      });
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      AppToast.info(context, 'Could not read the selected file');
      return;
    }
    if (bytes.length > LabReportFileStore.maxFileBytes) {
      if (!mounted) return;
      AppToast.info(context, 'File exceeds 8 MB limit');
      return;
    }

    setState(() => _file = file);
  }

  Future<void> _onSubmitPressed() async {
    final file = _file;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty) return;

    if (!await _confirmSubmit(file)) return;

    await _submit(file, bytes);
  }

  Future<void> _submit(PlatformFile file, Uint8List bytes) async {
    setState(() => _submitting = true);
    try {
      if (widget.booking != null) {
        final b = widget.booking!;
        final storageUrl = await FirestoreService.instance.labBooking.submitReport(
          bookingId: b.bookingId,
          patientId: b.patientId,
          fileName: LabReportFileStore.reportFileNameFor(
            testName: b.displayTestName,
            originalFileName: file.name,
          ),
          bytes: bytes,
          linkedBookingIds: b.linkedBookingIds,
        );

        LabWorklistStore.instance.applyBookingReportLocal(
          LabBookingRecord(
            bookingId: b.bookingId,
            labId: b.labId,
            labName: b.labName,
            patientId: b.patientId,
            patientName: b.patientName,
            testName: b.testName,
            testNames: b.testNames,
            groupedBookingIds: b.groupedBookingIds,
            dateTime: b.dateTime,
            slotLabel: b.slotLabel,
            collectionType: b.collectionType,
            address: b.address,
            status: 'completed',
            reportFileName: LabReportFileStore.reportFileNameFor(
              testName: b.displayTestName,
              originalFileName: file.name,
            ),
            reportStorageUrl: storageUrl,
            reportSubmittedAt: DateTime.now(),
            reportBookingId: b.bookingId,
          ),
        );
      } else if (widget.order != null) {
        final o = widget.order!;
        final reportFileName = LabReportFileStore.reportFileNameFor(
          testName: o.testNames.isNotEmpty ? o.testNames.join(', ') : 'Lab test',
          originalFileName: file.name,
        );
        final storageUrl = await FirestoreService.instance.labOrder.submitReport(
          orderId: o.orderId,
          patientId: o.patientId,
          fileName: reportFileName,
          bytes: bytes,
        );

        LabWorklistStore.instance.applyOrderReportLocal(
          DoctorLabOrder(
            orderId: o.orderId,
            doctorId: o.doctorId,
            doctorName: o.doctorName,
            patientId: o.patientId,
            patientName: o.patientName,
            patientAge: o.patientAge,
            testIds: o.testIds,
            testNames: o.testNames,
            createdAt: o.createdAt,
            appointmentId: o.appointmentId,
            labId: o.labId,
            labName: o.labName,
            indication: o.indication,
            urgency: o.urgency,
            fastingRequired: o.fastingRequired,
            homeCollection: o.homeCollection,
            source: o.source,
            status: 'completed',
            reportFileName: reportFileName,
            reportStorageUrl: storageUrl,
            reportSubmittedAt: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final String message;
      if (e is StateError) {
        message = e.message;
      } else if (e is FirebaseException) {
        final plugin = e.plugin;
        message = e.code == 'unauthorized' || e.code == 'permission-denied'
            ? plugin == 'firebase_storage'
                ? 'Upload denied — storage permission error (${e.code}). Contact support.'
                : 'Could not save report — permission error (${e.code}). Contact support.'
            : 'Upload failed: ${e.message ?? e.code}';
      } else if (e is TimeoutException) {
        message = 'Upload timed out. Check your connection and try again.';
      } else {
        message = 'Could not submit report: $e';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Upload lab report',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '$_patientName · $_testNames',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickFile,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(_file == null ? 'Choose PDF or image' : 'Change file'),
            ),
            if (_file != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardBgOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                child: Row(
                  children: [
                    Icon(
                      LabReportFileStore.isImageFile(_file!.name)
                          ? Icons.image_outlined
                          : Icons.picture_as_pdf_outlined,
                      color: AppColors.labPurple,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _file!.name,
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _formatFileSize(_file!.size),
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _file == null || _submitting ? null : _onSubmitPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.labPurple,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                    )
                  : const Text('Submit report to patient'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
