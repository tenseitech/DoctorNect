import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/multi_tag_input_field.dart';

const kCommonChiefComplaints = [
  'Chest Pain',
  'Stomach Ache',
  'Back Pain',
  'Skin Rash',
  'Difficulty Breathing',
  'Weakness',
  'Anxiety',
  'Insomnia',
];

/// Editable chief complaints for appointment detail — persists via [SharedAppointmentsStore].
class AppointmentChiefComplaintsSection extends StatefulWidget {
  const AppointmentChiefComplaintsSection({
    super.key,
    required this.recordId,
    required this.initialComplaints,
  });

  final String recordId;
  final List<String> initialComplaints;

  @override
  State<AppointmentChiefComplaintsSection> createState() =>
      _AppointmentChiefComplaintsSectionState();
}

class _AppointmentChiefComplaintsSectionState extends State<AppointmentChiefComplaintsSection> {
  late List<String> _complaints;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _complaints = List<String>.from(widget.initialComplaints);
  }

  @override
  void didUpdateWidget(covariant AppointmentChiefComplaintsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialComplaints != widget.initialComplaints) {
      _complaints = List<String>.from(widget.initialComplaints);
    }
  }

  void _add(String value) {
    final key = value.trim().toLowerCase();
    if (key.isEmpty || _complaints.any((c) => c.toLowerCase() == key)) return;
    setState(() => _complaints.add(value.trim()));
  }

  void _remove(String value) {
    setState(() {
      _complaints.removeWhere((c) => c.toLowerCase() == value.toLowerCase());
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await SharedAppointmentsStore.instance.saveChiefComplaints(
      recordId: widget.recordId,
      chiefComplaints: _complaints,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chief complaints saved'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Chief Complaints',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          MultiTagInputField(
            tags: _complaints,
            onAdd: _add,
            onRemove: _remove,
            hintText: 'Enter complaint',
            quickAddLabels: kCommonChiefComplaints,
            quickAddTitle: 'Common complaints',
            addButtonLabel: 'Add Complaint',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.doctorBlue,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: _saving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.surfaceOf(context),
                      ),
                    )
                  : Text(
                      'Save Complaints',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
