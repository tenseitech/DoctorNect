import '../../../core/notifications/app_toast.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/media/gallery_image_picker.dart';

import '../../../core/session/patient_session.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../../core/supabase/supabase_patient_repository.dart';
import '../../../core/theme/app_colors.dart';
import 'data/health_record_file_store.dart';
import 'models/health_record_models.dart';

class AddRecordScreen extends StatefulWidget {
  const AddRecordScreen({super.key});

  @override
  State<AddRecordScreen> createState() => _AddRecordScreenState();
}

class _AddRecordScreenState extends State<AddRecordScreen> {
  final _titleController = TextEditingController();
  final _doctorController = TextEditingController();
  final _facilityController = TextEditingController();
  final _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  HealthRecordType _type = HealthRecordType.prescription;
  DateTime _date = DateTime.now();
  bool _shareWithDoctors = false;
  bool _saving = false;
  final List<PlatformFile> _files = [];

  static const _types = [
    (HealthRecordType.prescription, 'Prescription'),
    (HealthRecordType.labReport, 'Lab Report'),
    (HealthRecordType.imaging, 'Imaging'),
    (HealthRecordType.discharge, 'Discharge Summary'),
    (HealthRecordType.vaccination, 'Vaccination'),
    (HealthRecordType.other, 'Insurance / Other'),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _doctorController.dispose();
    _facilityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickFiles() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photos'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Choose PDF files'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == 'image') {
      final images = await GalleryImagePicker.pickMultiple();
      if (images.isEmpty) return;

      final added = <PlatformFile>[];
      for (final image in images) {
        if (_files.length + added.length >= 5) break;
        if (image.bytes.length > HealthRecordFileStore.maxFileBytes) {
          if (!mounted) return;
          AppToast.info(context, '${image.name} exceeds 10 MB limit');
          continue;
        }
        added.add(PlatformFile(
          name: image.name,
          size: image.bytes.length,
          bytes: image.bytes,
          path: image.path,
        ));
      }
      if (added.isNotEmpty) setState(() => _files.addAll(added));
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    final added = <PlatformFile>[];
    for (final file in result.files) {
      if (_files.length + added.length >= 5) break;
      final bytes = file.bytes;
      if (bytes != null && bytes.length > HealthRecordFileStore.maxFileBytes) {
        if (!mounted) return;
        AppToast.info(context, '${file.name} exceeds 10 MB limit');
        continue;
      }
      added.add(file);
    }

    if (added.isNotEmpty) {
      setState(() => _files.addAll(added));
    }
  }

  bool _isImageFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
  }

  Future<Uint8List?> _fileBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes;
    if (!kIsWeb && file.path != null) {
      return File(file.path!).readAsBytes();
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _files.isEmpty) {
      AppToast.info(context, 'Please add at least one file');
      return;
    }

    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) {
      AppToast.info(context, 'Please sign in to save records');
      return;
    }

    final picked = _files.first;
    final bytes = await _fileBytes(picked);
    if (!mounted)
      return; // FIXED: mounted check before using context after await
    if (bytes == null || bytes.isEmpty) {
      AppToast.info(context, 'Could not read file. Please pick again.');
      return;
    }

    setState(() => _saving = true);

    final recordId = 'hr${DateTime.now().millisecondsSinceEpoch}';
    final fileName = picked.name;

    try {
      final saved = await HealthRecordFileStore.saveFile(
        patientId: patientId,
        recordId: recordId,
        fileName: fileName,
        bytes: bytes,
      );
      if (!saved) {
        if (!mounted) return;
        AppToast.info(context, 'File too large or could not be saved');
        return;
      }

      // Firebase Storage hook — no-op until bucket is configured.
      final storageUrl = await HealthRecordFileStore.uploadToFirebaseStorage(
        patientId: patientId,
        recordId: recordId,
        fileName: fileName,
        bytes: bytes,
      );

      // Persist to Supabase if available (guarded by PatientWriteGuard)
      if (SupabaseBootstrap.isReady) {
        try {
          await SupabasePatientRepository.instance.addHealthRecord(
            context: context,
            recordId: recordId,
            patientId: patientId,
            title: _titleController.text.trim(),
            type: _type.name,
            date: _date,
            source: 'selfUploaded',
            fileName: fileName,
            doctorName: _doctorController.text.trim().isEmpty
                ? null
                : _doctorController.text.trim(),
            labName: _facilityController.text.trim().isEmpty
                ? null
                : _facilityController.text.trim(),
            isImage: _isImageFile(fileName),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            sharedWithDoctors: _shareWithDoctors,
            fileStorage: storageUrl != null ? 'cloudUploaded' : 'localOnly',
            storageUrl: storageUrl,
          );
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.pop(
        context,
        HealthRecord(
          id: recordId,
          title: _titleController.text.trim(),
          type: _type,
          date: _date,
          source: RecordSource.selfUploaded,
          fileName: fileName,
          doctorName: _doctorController.text.trim().isEmpty
              ? null
              : _doctorController.text.trim(),
          labName: _facilityController.text.trim().isEmpty
              ? null
              : _facilityController.text.trim(),
          isImage: _isImageFile(fileName),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          sharedWithDoctors: _shareWithDoctors,
          fileStorage: storageUrl != null
              ? HealthRecordFileStorage.firebase
              : HealthRecordFileStorage.local,
          storageUrl: storageUrl,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      appBar: AppBar(
        title: Text('Add Record',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Record title'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<HealthRecordType>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Record type'),
              items: _types
                  .map((t) => DropdownMenuItem(value: t.$1, child: Text(t.$2)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _doctorController,
              decoration:
                  const InputDecoration(labelText: 'Doctor name (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _facilityController,
              decoration:
                  const InputDecoration(labelText: 'Hospital / Lab name'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Record date'),
              subtitle: Text(DateFormat('dd MMM yyyy').format(_date)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickFiles,
              icon: const Icon(Icons.upload_file),
              label:
                  Text('Upload file (PDF/image, max 10MB) — ${_files.length}'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.patientTeal),
            ),
            ..._files.map(
              (f) => ListTile(
                dense: true,
                title: Text(f.name),
                leading: const Icon(Icons.attach_file, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Notes', alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share with my doctors'),
              subtitle: const Text('Off = Private'),
              value: _shareWithDoctors,
              onChanged: (v) => setState(() => _shareWithDoctors = v),
              activeThumbColor: AppColors.patientTeal,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.patientTeal,
                minimumSize: const Size(double.infinity, 52),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.white),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
