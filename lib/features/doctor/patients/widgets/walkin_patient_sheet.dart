import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/constants/country_phone_codes.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/phone_number_field.dart';
import '../../../../widgets/required_field_label.dart';
import '../../../../widgets/multi_tag_input_field.dart';
import '../../profile/data/doctor_profile_store.dart';

class WalkInPatientSheet extends StatefulWidget {
  const WalkInPatientSheet({super.key});

  static Future<bool> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const WalkInPatientSheet(),
      ),
    ).then((value) => value ?? false);
  }

  @override
  State<WalkInPatientSheet> createState() => _WalkInPatientSheetState();
}

class _WalkInPatientSheetState extends State<WalkInPatientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  final List<String> _chiefComplaints = [];

  String _gender = AppConstants.genders.first;
  DateTime _dateTime = DateTime.now();
  bool _submitting = false;
  String _phoneDialCode = CountryPhoneCodes.defaultDialCode;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initialDate = _dateTime.isBefore(now) ? now : _dateTime;
    
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now, // Block back dates
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.doctorBlue),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.doctorBlue),
        ),
        child: child!,
      ),
    );
    if (!mounted) return;

    setState(() {
      _dateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _dateTime.hour,
        time?.minute ?? _dateTime.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    final name = _nameController.text.trim();
    final age = int.tryParse(_ageController.text.trim());
    if (age == null) return;

    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isEmpty) {
      _snack('Doctor session not found. Please sign in again.');
      return;
    }

    setState(() => _submitting = true);

    final profile = DoctorProfileStore.instance.profile;
    final doctorName = profile.fullName.trim().isNotEmpty
        ? profile.fullName.trim()
        : DoctorSession.loggedInDoctorName;

    final ok = await SharedAppointmentsStore.instance.addWalkInAppointment(
      doctorId: doctorId,
      doctorName: doctorName,
      specialization: profile.specialization,
      patientName: name,
      patientAge: age,
      patientGender: _gender,
      dateTime: _dateTime,
      contactNumber: FormValidators.formatFullPhone(
        _phoneDialCode,
        _phoneController.text.trim(),
      ),
      chiefComplaints: _chiefComplaints,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      Navigator.pop(context, true);
    } else {
      _snack('Could not add walk-in patient');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEE, dd MMM yyyy · hh:mm a').format(_dateTime);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add Walk-in Patient',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Register a patient who is at the clinic without an app booking.',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                ],
                decoration: RequiredFieldLabels.decorate(
                  const InputDecoration(),
                  'Patient Name',
                  isRequired: true,
                ),
                validator: FormValidators.patientName,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: RequiredFieldLabels.decorate(
                        const InputDecoration(),
                        'Age',
                        isRequired: true,
                      ),
                      validator: FormValidators.walkInAge,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: RequiredFieldLabels.decorate(
                        const InputDecoration(),
                        'Gender',
                        isRequired: true,
                      ),
                      items: AppConstants.genders
                          .map(
                            (gender) => DropdownMenuItem(
                              value: gender,
                              child: Text(gender),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _gender = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PhoneNumberField(
                controller: _phoneController,
                initialDialCode: _phoneDialCode,
                onDialCodeChanged: (code) => _phoneDialCode = code,
                labelText: 'Phone Number',
                isRequired: true,
                validator: (v) => FormValidators.phoneLocal(v, dialCode: _phoneDialCode),
              ),
              const SizedBox(height: 12),
              MultiTagInputField(
                label: 'Chief Complaint / Reason for Visit (optional)',
                hintText: 'Enter complaint',
                addButtonLabel: '+ Add Entry',
                tags: _chiefComplaints,
                onAdd: (value) => setState(() {
                  if (!_chiefComplaints.any((c) => c.toLowerCase() == value.toLowerCase())) {
                    _chiefComplaints.add(value);
                  }
                }),
                onRemove: (value) => setState(
                  () => _chiefComplaints.removeWhere(
                    (c) => c.toLowerCase() == value.toLowerCase(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickDateTime,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(dateLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.doctorBlue,
                  side: const BorderSide(color: AppColors.doctorBlue),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  alignment: Alignment.centerLeft,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.doctorBlue,
                  minimumSize: Size(double.infinity, 48),
                ),
                child: _submitting
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.surfaceOf(context),
                        ),
                      )
                    : const Text('Add Patient'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
