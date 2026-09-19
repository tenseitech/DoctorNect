import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

enum MedicationTimeSlot { morning, afternoon, evening, night }

abstract final class MedicationTimeSlots {
  static String label(MedicationTimeSlot slot) {
    return switch (slot) {
      MedicationTimeSlot.morning => 'Morning',
      MedicationTimeSlot.afternoon => 'Afternoon',
      MedicationTimeSlot.evening => 'Evening',
      MedicationTimeSlot.night => 'Night',
    };
  }

  static String rangeLabel(MedicationTimeSlot slot) {
    return switch (slot) {
      MedicationTimeSlot.morning => '6:00 AM – 12:00 PM',
      MedicationTimeSlot.afternoon => '12:00 PM – 4:00 PM',
      MedicationTimeSlot.evening => '4:00 PM – 8:00 PM',
      MedicationTimeSlot.night => '8:00 PM – 6:00 AM',
    };
  }

  static TimeOfDay defaultTime(MedicationTimeSlot slot) {
    return switch (slot) {
      MedicationTimeSlot.morning => const TimeOfDay(hour: 8, minute: 0),
      MedicationTimeSlot.afternoon => const TimeOfDay(hour: 13, minute: 0),
      MedicationTimeSlot.evening => const TimeOfDay(hour: 17, minute: 0),
      MedicationTimeSlot.night => const TimeOfDay(hour: 20, minute: 0),
    };
  }

  static bool isValid(MedicationTimeSlot slot, TimeOfDay time) {
    final totalMinutes = time.hour * 60 + time.minute;
    return switch (slot) {
      MedicationTimeSlot.morning => totalMinutes >= 6 * 60 && totalMinutes < 12 * 60,
      MedicationTimeSlot.afternoon => totalMinutes >= 12 * 60 && totalMinutes < 16 * 60,
      MedicationTimeSlot.evening => totalMinutes >= 16 * 60 && totalMinutes < 20 * 60,
      MedicationTimeSlot.night =>
          totalMinutes >= 20 * 60 || totalMinutes < 6 * 60,
    };
  }

  static TimeOfDay? parseFormattedTime(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.trim().split(' ');
    if (parts.isEmpty) return null;

    final timeParts = parts.first.split(':');
    if (timeParts.length != 2) return null;

    var hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (hour == null || minute == null) return null;

    if (parts.length > 1) {
      final period = parts[1].toUpperCase();
      if (period == 'PM' && hour != 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  static List<int> hoursFor(MedicationTimeSlot slot) {
    return switch (slot) {
      MedicationTimeSlot.morning => List<int>.generate(6, (i) => i + 6),
      MedicationTimeSlot.afternoon => List<int>.generate(4, (i) => i + 12),
      MedicationTimeSlot.evening => List<int>.generate(4, (i) => i + 16),
      MedicationTimeSlot.night => [20, 21, 22, 23, 0, 1, 2, 3, 4, 5],
    };
  }

  static Future<String?> pickTime(
    BuildContext context,
    MedicationTimeSlot slot, {
    String? current,
  }) async {
    final parsed = parseFormattedTime(current);
    var selected = parsed != null && isValid(slot, parsed) ? parsed : defaultTime(slot);
    final hours = hoursFor(slot);

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (!hours.contains(selected.hour)) {
              selected = TimeOfDay(hour: hours.first, minute: 0);
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  16 + MediaQuery.viewInsetsOf(context).bottom,
                ),
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
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${label(slot)} time',
                      style: GoogleFonts.inter(fontSize: AppTypography.headlineSmall, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select between ${rangeLabel(slot)}',
                      style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selected.hour,
                            decoration: const InputDecoration(labelText: 'Hour'),
                            items: [
                              for (final hour in hours)
                                DropdownMenuItem(
                                  value: hour,
                                  child: Text(_formatHour(hour)),
                                ),
                            ],
                            onChanged: (hour) {
                              if (hour == null) return;
                              setSheetState(() => selected = TimeOfDay(hour: hour, minute: selected.minute));
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selected.minute,
                            decoration: const InputDecoration(labelText: 'Minute'),
                            items: [
                              for (var minute = 0; minute < 60; minute++)
                                DropdownMenuItem(
                                  value: minute,
                                  child: Text(minute.toString().padLeft(2, '0')),
                                ),
                            ],
                            onChanged: (minute) {
                              if (minute == null) return;
                              setSheetState(() => selected = TimeOfDay(hour: selected.hour, minute: minute));
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              if (!isValid(slot, selected)) return;
                              Navigator.pop(sheetContext, selected.format(context));
                            },
                            style: FilledButton.styleFrom(backgroundColor: AppColors.patientTeal),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _formatHour(int hour24) {
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12 $period';
  }
}
