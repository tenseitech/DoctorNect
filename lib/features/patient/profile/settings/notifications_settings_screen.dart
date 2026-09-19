import '../../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  State<NotificationsSettingsScreen> createState() => _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState extends State<NotificationsSettingsScreen> {
  NotificationPrefs get _p => PatientProfileMock.notificationPrefs;

  void _persist() {
    widget.onChanged();
    unawaited(PatientProfileMock.persistCurrentProfile());
    InAppNotificationService.instance.onPatientNotificationPrefsChanged();
    if (_p.medicationReminders) {
      unawaited(MedicationReminderService.updateScheduledReminders(_p.medications));
    } else {
      unawaited(MedicationReminderService.cancelAllReminders());
    }
  }

  void _addMedication() {
    final formKey = GlobalKey<FormState>();
    String? morningTime;
    String? afternoonTime;
    String? eveningTime;
    String? nightTime;

    showDialog(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Widget buildTimeRow(MedicationTimeSlot slot, String? time, ValueChanged<String?> onChanged) {
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
                          onChanged(MedicationTimeSlots.defaultTime(slot).format(context));
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
                          Text(title, style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w600)),
                          Text(
                            MedicationTimeSlots.rangeLabel(slot),
                            style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
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
                        style: TextButton.styleFrom(foregroundColor: AppColors.patientTeal),
                        child: Text(time, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: const Text('Add medicine'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Medicine name'),
                        validator: (v) => FormValidators.tagText(v, field: 'Medicine name'),
                      ),
                      const SizedBox(height: 16),
                      buildTimeRow(
                        MedicationTimeSlot.morning,
                        morningTime,
                        (t) => setStateDialog(() => morningTime = t),
                      ),
                      buildTimeRow(
                        MedicationTimeSlot.afternoon,
                        afternoonTime,
                        (t) => setStateDialog(() => afternoonTime = t),
                      ),
                      buildTimeRow(
                        MedicationTimeSlot.evening,
                        eveningTime,
                        (t) => setStateDialog(() => eveningTime = t),
                      ),
                      buildTimeRow(
                        MedicationTimeSlot.night,
                        nightTime,
                        (t) => setStateDialog(() => nightTime = t),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondaryOf(context)),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    if (morningTime == null &&
                        afternoonTime == null &&
                        eveningTime == null &&
                        nightTime == null) {
                      AppToast.info(context, 'Please select at least one time.');
                      return;
                    }
                    setState(() {
                      _p.medications.add(MedicationReminder(
                        name: nameCtrl.text.trim(),
                        morningTime: morningTime,
                        afternoonTime: afternoonTime,
                        eveningTime: eveningTime,
                        nightTime: nightTime,
                      ));
                    });
                    _persist();
                    Navigator.pop(ctx);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.patientTeal,
                    foregroundColor: AppColors.white,
                  ),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('Notifications', context: context),
      body: PatientProfileFormStyles.constrainedScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'All alerts are delivered inside DoctorNect. Push/SMS/WhatsApp tags show alert type only — nothing is sent outside the app.',
                    style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
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
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
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
                            const Icon(Icons.medication_outlined, color: AppColors.patientTeal, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.name),
                                  Text([
                                    if (m.morningTime != null) 'Morning (${m.morningTime})',
                                    if (m.afternoonTime != null) 'Afternoon (${m.afternoonTime})',
                                    if (m.eveningTime != null) 'Evening (${m.eveningTime})',
                                    if (m.nightTime != null) 'Night (${m.nightTime})',
                                  ].join(' • '), style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context))),
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
