import '../../../../core/notifications/app_toast.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/notifications/in_app_notification_service.dart';
import '../../../../core/notifications/medication_reminder_service.dart';
import '../../../../core/validators/form_validators.dart';
import '../data/patient_profile_mock.dart';
import '../models/patient_profile_models.dart';
import '../../../../widgets/labeled_remove_button.dart';
import '../utils/medication_time_slots.dart';
import '../widgets/patient_profile_form_styles.dart';
import '../../../../core/theme/app_typography.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  NotificationPrefs get _p => PatientProfileMock.notificationPrefs;

  void _persist() {
    widget.onChanged();
    unawaited(PatientProfileMock.persistCurrentProfile());
    InAppNotificationService.instance.onPatientNotificationPrefsChanged();
    if (_p.medicationReminders) {
      unawaited(
        MedicationReminderService.updateScheduledReminders(_p.medications),
      );
    } else {
      unawaited(MedicationReminderService.cancelAllReminders());
    }
  }

  Future<void> _addMedication() async {
    final reminder = await showDialog<MedicationReminder>(
      context: context,
      builder: (ctx) => const _AddMedicationDialog(),
    );
    if (reminder != null && mounted) {
      setState(() {
        _p.medications.add(reminder);
      });
      _persist();
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar(
        'Notifications',
        context: context,
      ),
      body: PatientProfileFormStyles.constrainedScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PatientProfileFormStyles.contentSurface(
              context: context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'All alerts are delivered inside DoctorNect. Push/SMS/WhatsApp tags show alert type only — nothing is sent outside the app.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppTypography.labelMedium,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Appointment reminders'),
                    value: _p.appointmentReminders,
                    onChanged: (v) => setState(() {
                      _p.appointmentReminders = v;
                      _persist();
                    }),
                    activeThumbColor: AppColors.patientTeal,
                  ),
                  if (_p.appointmentReminders) ...[
                    PatientProfileFormStyles.sectionHeader('Remind me'),
                    const SizedBox(height: 8),
                    RadioGroup<ReminderTiming>(
                      groupValue: _p.reminderTiming,
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _p.reminderTiming = v;
                            _persist();
                          });
                        }
                      },
                      child: Column(
                        children: [
                          RadioListTile<ReminderTiming>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('1 hour before'),
                            value: ReminderTiming.oneHour,
                            activeColor: AppColors.patientTeal,
                          ),
                          RadioListTile<ReminderTiming>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('2 hours before'),
                            value: ReminderTiming.twoHours,
                            activeColor: AppColors.patientTeal,
                          ),
                          RadioListTile<ReminderTiming>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('1 day before'),
                            value: ReminderTiming.oneDay,
                            activeColor: AppColors.patientTeal,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            PatientProfileFormStyles.contentSurface(
              context: context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Medication reminders'),
                    value: _p.medicationReminders,
                    onChanged: (v) => setState(() {
                      _p.medicationReminders = v;
                      _persist();
                    }),
                    activeThumbColor: AppColors.patientTeal,
                  ),
                  if (_p.medicationReminders) ...[
                    const SizedBox(height: 8),
                    ..._p.medications.map(
                      (m) => PatientProfileFormStyles.recordItemCard(
                        context: context,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.medication_outlined,
                              color: AppColors.patientTeal,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.name),
                                  Text(
                                    [
                                      if (m.morningTime != null)
                                        'Morning (${m.morningTime})',
                                      if (m.afternoonTime != null)
                                        'Afternoon (${m.afternoonTime})',
                                      if (m.eveningTime != null)
                                        'Evening (${m.eveningTime})',
                                      if (m.nightTime != null)
                                        'Night (${m.nightTime})',
                                    ].join(' • '),
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: AppTypography.labelMedium,
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            LabeledRemoveButton(
                              onPressed: () {
                                setState(() => _p.medications.remove(m));
                                _persist();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _addMedication,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add medicine'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.patientTeal,
                          foregroundColor: AppColors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMedicationDialog extends StatefulWidget {
  const _AddMedicationDialog();

  @override
  State<_AddMedicationDialog> createState() => _AddMedicationDialogState();
}

class _AddMedicationDialogState extends State<_AddMedicationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  String? _morningTime;
  String? _afternoonTime;
  String? _eveningTime;
  String? _nightTime;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Widget _buildTimeRow(
    BuildContext context,
    MedicationTimeSlot slot,
    String? time,
    ValueChanged<String?> onChanged,
  ) {
    final title = MedicationTimeSlots.label(slot);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: time != null,
            onChanged: (checked) {
              if (checked == true) {
                onChanged(
                  MedicationTimeSlots.defaultTime(slot).format(context),
                );
              } else {
                onChanged(null);
              }
            },
            activeColor: AppColors.patientTeal,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  MedicationTimeSlots.rangeLabel(slot),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.labelSmall,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          if (time != null)
            TextButton(
              onPressed: () async {
                final picked = await MedicationTimeSlots.pickTime(
                  context,
                  slot,
                  current: time,
                );
                if (picked != null) onChanged(picked);
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.patientTeal,
              ),
              child: Text(
                time,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add medicine'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Medicine name',
                ),
                validator: (v) =>
                    FormValidators.tagText(v, field: 'Medicine name'),
              ),
              const SizedBox(height: 16),
              _buildTimeRow(
                context,
                MedicationTimeSlot.morning,
                _morningTime,
                (t) => setState(() => _morningTime = t),
              ),
              _buildTimeRow(
                context,
                MedicationTimeSlot.afternoon,
                _afternoonTime,
                (t) => setState(() => _afternoonTime = t),
              ),
              _buildTimeRow(
                context,
                MedicationTimeSlot.evening,
                _eveningTime,
                (t) => setState(() => _eveningTime = t),
              ),
              _buildTimeRow(
                context,
                MedicationTimeSlot.night,
                _nightTime,
                (t) => setState(() => _nightTime = t),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondaryOf(context),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            if (_morningTime == null &&
                _afternoonTime == null &&
                _eveningTime == null &&
                _nightTime == null) {
              AppToast.info(
                context,
                'Please select at least one time.',
              );
              return;
            }
            final reminder = MedicationReminder(
              name: _nameCtrl.text.trim(),
              morningTime: _morningTime,
              afternoonTime: _afternoonTime,
              eveningTime: _eveningTime,
              nightTime: _nightTime,
            );
            Navigator.pop(context, reminder);
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.patientTeal,
            foregroundColor: AppColors.white,
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
