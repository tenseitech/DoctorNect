import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/firebase/firebase_bootstrap.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/community_medicine_repository.dart';
import '../data/dosage_units.dart';

class AddCommunityMedicineDialog extends StatefulWidget {
  const AddCommunityMedicineDialog({super.key, required this.initialName});

  final String initialName;

  static Future<CommunityMedicine?> show(
      BuildContext context, String initialName) {
    return showDialog<CommunityMedicine>(
      context: context,
      builder: (ctx) => AddCommunityMedicineDialog(initialName: initialName),
    );
  }

  @override
  State<AddCommunityMedicineDialog> createState() =>
      _AddCommunityMedicineDialogState();
}

class _AddCommunityMedicineDialogState
    extends State<AddCommunityMedicineDialog> {
  late final TextEditingController _nameController;
  String _dosageUnit = kDosageUnits.first;
  String _form = kCommunityMedicineForms.first;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppToast.info(context, 'Medicine name is required');
      return;
    }

    if (!FirebaseBootstrap.isReady) {
      AppToast.info(context, 'Internet is required to add medicine.');
      return;
    }

    final doctorId = DoctorSession.loggedInDoctorId.trim();
    if (doctorId.isEmpty) {
      AppToast.info(context, 'Doctor session not found. Please login again.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final medicine = await CommunityMedicineRepository.instance.addMedicine(
        name: name,
        dosageUnit: _dosageUnit,
        form: _form,
        doctorId: doctorId,
      );
      if (!mounted) return;
      if (medicine != null) {
        Navigator.pop(context, medicine);
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.info(context, 'Could not add medicine: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Medicine to Database?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Medicine Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _dosageUnit,
              decoration: const InputDecoration(labelText: 'Dosage unit'),
              items: kDosageUnits
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _dosageUnit = v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _form,
              decoration: const InputDecoration(labelText: 'Form'),
              items: kCommunityMedicineForms
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _form = v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.doctorBlue),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Add to Database'),
        ),
      ],
    );
  }
}
