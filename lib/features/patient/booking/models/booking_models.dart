import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum SlotStatus { available, selected, booked }

enum SlotShareReasonType { emergency, other }

/// Maximum patients allowed on the same time slot per doctor per day.
const kMaxPatientsPerTimeSlot = 3;

final _slotParseFormat = DateFormat('hh:mm a');

/// True when [slotLabel] on [date] is today and its start time has already passed.
bool isSlotTimeInPast(DateTime date, String slotLabel,
    [DateTime? referenceTime]) {
  final now = referenceTime ?? DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day.isBefore(today)) return true;
  if (day.isAfter(today)) return false;
  try {
    final parsed = _slotParseFormat.parse(slotLabel.trim());
    final slotStart =
        DateTime(day.year, day.month, day.day, parsed.hour, parsed.minute);
    return !slotStart.isAfter(now);
  } catch (_) {
    return false;
  }
}

/// Formats [time] as a 12-hour slot label (e.g. `10:30 AM`).
String formatSlotTimeLabel(TimeOfDay time) {
  return _slotParseFormat.format(
    DateTime(2000, 1, 1, time.hour, time.minute),
  );
}

/// Parses a slot label into [TimeOfDay], or null if invalid.
TimeOfDay? parseSlotTimeLabel(String? label) {
  if (label == null || label.trim().isEmpty) return null;
  try {
    final parsed = _slotParseFormat.parse(label.trim());
    return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
  } catch (_) {
    return null;
  }
}

bool slotLabelsMatch(String a, String b) {
  try {
    final na = _slotParseFormat.format(_slotParseFormat.parse(a.trim()));
    final nb = _slotParseFormat.format(_slotParseFormat.parse(b.trim()));
    return na == nb;
  } catch (_) {
    return false;
  }
}

/// Picks the best matching selectable slot for a chosen time.
TimeSlot? matchSlotForTime(List<TimeSlot> slots, TimeOfDay time) {
  if (slots.isEmpty) return null;

  final pickedLabel = formatSlotTimeLabel(time);
  for (final slot in slots) {
    if (slotLabelsMatch(slot.label, pickedLabel)) return slot;
  }

  final pickedMinutes = time.hour * 60 + time.minute;
  TimeSlot? nearest;
  var smallestDiff = 1 << 30;

  for (final slot in slots) {
    final slotTime = parseSlotTimeLabel(slot.label);
    if (slotTime == null) continue;
    final slotMinutes = slotTime.hour * 60 + slotTime.minute;
    final diff = (slotMinutes - pickedMinutes).abs();
    if (diff < smallestDiff) {
      smallestDiff = diff;
      nearest = slot;
    }
  }

  return nearest;
}

class TimeSlot {
  const TimeSlot({
    required this.id,
    required this.label,
    required this.period,
    this.status = SlotStatus.available,
    this.bookingCount = 0,
  });

  final String id;
  final String label;
  final String period;
  final SlotStatus status;
  final int bookingCount;

  bool get isFull => bookingCount >= kMaxPatientsPerTimeSlot;
  bool get isSelectable => status == SlotStatus.available;
  bool get requiresShareReason => bookingCount >= 1 && !isFull;
  int get remainingCapacity => kMaxPatientsPerTimeSlot - bookingCount;
}

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    required this.age,
    required this.relation,
    required this.gender,
  });

  final String id;
  final String name;
  final int age;
  final String relation;
  final String gender;
}

class BookingDraft {
  BookingDraft({
    required this.doctorId,
    required this.doctorName,
    this.selectedDate,
    this.selectedSlotId,
    this.selectedSlotLabel,
    this.bookingForSelf = true,
    List<String>? familyMemberIds,
    this.selfReason = '',
    Map<String, String>? memberReasons,
    List<String>? symptoms,
    List<String>? reportFiles,
    this.slotShareReasonType,
    this.slotShareReasonText = '',
  })  : familyMemberIds = List<String>.from(familyMemberIds ?? const []),
        memberReasons = Map<String, String>.from(memberReasons ?? const {}),
        symptoms = List<String>.from(symptoms ?? const []),
        reportFiles = List<String>.from(reportFiles ?? const []);

  final String doctorId;
  final String doctorName;
  DateTime? selectedDate;
  String? selectedSlotId;
  String? selectedSlotLabel;
  bool bookingForSelf;
  List<String> familyMemberIds;
  String selfReason;
  Map<String, String> memberReasons;
  List<String> symptoms;
  List<String> reportFiles;
  SlotShareReasonType? slotShareReasonType;
  String slotShareReasonText;
}

class ConfirmedBooking {
  const ConfirmedBooking({
    required this.appointmentId,
    required this.tokenNumber,
    required this.doctorName,
    required this.date,
    required this.slotLabel,
    required this.patientName,
    required this.clinicAddress,
    this.awaitingDoctorApproval = false,
  });

  final String appointmentId;
  final int tokenNumber;
  final String doctorName;
  final DateTime date;
  final String slotLabel;
  final String patientName;
  final String? clinicAddress;
  final bool awaitingDoctorApproval;
}
