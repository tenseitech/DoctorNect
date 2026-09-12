import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';

import '../../../../core/session/doctor_session.dart'; // FIXED: doctor id for Firestore persist
import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/required_field_label.dart';
import '../data/doctor_profile_store.dart';
import '../widgets/profile_widgets.dart';
import '../widgets/section_save_bar.dart';

class ConsultationSettingsSection extends StatefulWidget {
  const ConsultationSettingsSection({super.key});

  @override
  State<ConsultationSettingsSection> createState() => _ConsultationSettingsSectionState();
}

class _ConsultationSettingsSectionState extends State<ConsultationSettingsSection> {
  static const _bookingDays = [1, 3, 7, 15, 30];

  final _formKey = GlobalKey<FormState>();

  late final _duration = TextEditingController(text: '${_p.avgDurationMins}');
  late final _maxPatients = TextEditingController(text: '${_p.maxPatientsPerDay}');
  late int _advanceDays = _p.advanceBookingDays;
  late bool _autoAccept = _p.autoAcceptAppointments;
  late bool _apptReminders = _p.appointmentReminders;
  late final _remindHours = TextEditingController(text: '${_p.remindHoursBefore}');
  bool _dirty = false;

  DoctorProfileData get _p => DoctorProfileStore.instance.profile;

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _p.avgDurationMins = int.parse(_duration.text.trim());
    _p.maxPatientsPerDay = int.tryParse(_maxPatients.text) ?? _p.maxPatientsPerDay;
    _p.advanceBookingDays = _advanceDays;
    _p.autoAcceptAppointments = _autoAccept;
    _p.appointmentReminders = _apptReminders;
    _p.remindHoursBefore = int.parse(_remindHours.text.trim());

    // FIXED: await Firestore write; only show success / pop on confirmed save.
    try {
      await DoctorProfileStore.instance.persist(DoctorSession.loggedInDoctorId);
    } catch (_) {
      if (!mounted) return; // FIXED: mounted check after await
      AppToast.info(context, 'Could not save changes. Please check your connection and try again.');
      return;
    }
    if (!mounted) return; // FIXED: mounted check after await
    setState(() => _dirty = false);
    showProfileSavedToast(context);
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _duration.dispose();
    _maxPatients.dispose();
    _remindHours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consultation Settings')),
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-accept appointments'),
                  subtitle: Text(
                    _autoAccept
                        ? 'New patient requests are confirmed instantly.'
                        : 'You review each request and tap Accept or Decline.',
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  value: _autoAccept,
                  onChanged: (v) {
                    setState(() => _autoAccept = v);
                    _markDirty();
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: RequiredFieldLabels.decorate(
                    const InputDecoration(
                      suffixText: 'mins',
                      helperText: 'Minimum 5 minutes',
                    ),
                    'Avg consultation duration (mins)',
                    isRequired: true,
                  ),
                  validator: FormValidators.consultationDuration,
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxPatients,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(labelText: 'Max patients per day'),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 16),
                Text('Advance booking allowed', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _bookingDays.map((d) {
                    return ChoiceChip(
                      label: Text('$d days'),
                      selected: _advanceDays == d,
                      onSelected: (_) {
                        setState(() => _advanceDays = d);
                        _markDirty();
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Appointment Reminders', style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Send reminders to patients'),
                  subtitle: Text(
                    _apptReminders
                        ? 'Patients receive automated reminder alerts before their appointment.'
                        : 'No reminders will be sent.',
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  value: _apptReminders,
                  activeTrackColor: AppColors.doctorBlue.withValues(alpha: 0.5),
                  activeThumbColor: AppColors.doctorBlue,
                  onChanged: (v) {
                    setState(() => _apptReminders = v);
                    _markDirty();
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _remindHours,
                  enabled: _apptReminders,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: RequiredFieldLabels.decorate(
                    const InputDecoration(
                      suffixText: 'hours',
                      helperText: 'Minimum 1 hour, maximum 24 hours',
                    ),
                    'Remind patients X hours before',
                    isRequired: _apptReminders,
                  ),
                  validator: (v) => _apptReminders ? FormValidators.reminderHours(v) : null,
                  onChanged: (_) => _markDirty(),
                ),
              ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SectionSaveBar(visible: _dirty, onSave: _save),
        ],
      ),
    );
  }
}
