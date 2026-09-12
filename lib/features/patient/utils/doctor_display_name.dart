import 'package:medibond/features/patient/models/patient_models.dart';

String formatDoctorDisplayName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Doctor';

  final lower = trimmed.toLowerCase();
  if (lower.startsWith('dr.') || lower.startsWith('dr ')) {
    final withoutPrefix = trimmed.replaceFirst(RegExp(r'^dr\.?\s*', caseSensitive: false), '').trim();
    if (withoutPrefix.isEmpty) return 'Doctor';
    return 'Dr. $withoutPrefix';
  }
  return 'Dr. $trimmed';
}

String formatExperienceYears(int years) {
  if (years <= 0) return 'New to platform';
  if (years == 1) return '1 year experience';
  return '$years years experience';
}

String formatAvailabilityLabel(DoctorAvailability availability, String nextSlot) {
  final slot = nextSlot.trim();
  if (slot.isNotEmpty && slot.toLowerCase() != 'check availability') {
    return slot;
  }
  return switch (availability) {
    DoctorAvailability.today => 'Available today',
    DoctorAvailability.tomorrow => 'Available tomorrow',
    DoctorAvailability.later => 'Check availability',
  };
}
