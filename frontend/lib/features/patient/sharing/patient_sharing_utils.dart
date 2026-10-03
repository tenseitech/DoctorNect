import '../../../features/patient/booking/models/booking_models.dart';
import '../../../features/patient/records/models/health_record_models.dart';

/// Pure helpers for patient sharing (privacy, slot share, family booking metadata).
abstract final class PatientSharingUtils {
  PatientSharingUtils._();

  /// Invite-link registration opts in to sharing with the inviting doctor.
  static bool deriveInitialShareRecordsWithDoctors(String? invitedDoctorId) =>
      invitedDoctorId != null && invitedDoctorId.isNotEmpty;

  static String? resolveSlotShareReason({
    required int existingSlotBookings,
    required SlotShareReasonType? type,
    required String reasonText,
  }) {
    if (existingSlotBookings < 1) return null;
    return switch (type) {
      SlotShareReasonType.emergency => 'Emergency',
      SlotShareReasonType.other => reasonText.trim(),
      null => null,
    };
  }

  static bool isSlotShareStepValid({
    required bool slotSelectable,
    required int existingSlotBookings,
    required SlotShareReasonType? type,
    required String reasonText,
  }) {
    if (!slotSelectable) return false;
    if (existingSlotBookings >= 1) {
      if (type == null) return false;
      if (type == SlotShareReasonType.other && reasonText.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  static bool hasSlotCapacityForPatients({
    required int existingSlotBookings,
    required int patientCount,
  }) =>
      existingSlotBookings + patientCount <= kMaxPatientsPerTimeSlot;

  static List<HealthRecord> filterHealthRecordsSharedWithDoctors(
    List<HealthRecord> records,
  ) =>
      records.where((record) => record.sharedWithDoctors).toList();
}
