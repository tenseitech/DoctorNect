import '../../../../core/firebase/firestore_service.dart';
import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/firebase/models/doctor_availability.dart';
import '../../../patient/data/registered_doctors_store.dart';
import '../../profile/models/doctor_profile_data.dart';
import '../models/clinical_models.dart';

/// Real doctor/clinic header lines for prescriptions (PDF, preview, form).
abstract final class PrescriptionHeaderHelper {
  static String? _timingsCache;

  static String get fallbackTimings => 'See clinic schedule when booking';

  /// Doctor name to print on a prescription.
  ///
  /// Sourced from the patient's booking/appointment record so it reflects the
  /// doctor the patient actually consulted — not whoever happens to be signed
  /// in. Falls back to the prescription's own saved snapshot, then [fallback].
  static String doctorNameForDraft(PrescriptionDraft draft, {String? fallback}) {
    // 1. The exact booking this prescription was written against.
    final booked = _bookingDoctorName(draft.patient.appointmentId);
    if (booked != null && booked.isNotEmpty) return booked;

    // 2. Resolve by doctorId (always saved on the prescription) from the
    //    patient's bookings or the live doctor directory. Covers prescriptions
    //    whose doctorName snapshot was never saved / was left generic.
    final byId = _doctorNameById(draft.doctorId);
    if (byId != null && byId.isNotEmpty) return byId;

    // 3. The snapshot saved on the prescription itself.
    final snapshot = draft.doctorName.trim();
    if (snapshot.isNotEmpty) return snapshot;

    return fallback ?? '';
  }

  static String? _bookingDoctorName(String? appointmentId) {
    if (appointmentId == null || appointmentId.isEmpty) return null;
    final appointment =
        SharedAppointmentsStore.instance.patientAppointmentForTarget(appointmentId);
    return _withPrefix(appointment?.doctorName);
  }

  static String? _doctorNameById(String doctorId) {
    if (doctorId.trim().isEmpty) return null;
    // Prefer the name captured on any of the patient's bookings with this doctor.
    for (final record in SharedAppointmentsStore.instance.records) {
      if (record.doctorId == doctorId) {
        final name = _withPrefix(record.doctorName);
        if (name != null) return name;
      }
    }
    // Fall back to the live doctor directory.
    return _withPrefix(RegisteredDoctorsStore.instance.findById(doctorId)?.name);
  }

  static String? _withPrefix(String? raw) {
    final name = raw?.trim() ?? '';
    if (name.isEmpty) return null;
    return name.startsWith('Dr.') ? name : 'Dr. $name';
  }

  static String qualificationsLine(DoctorProfileData profile) {
    if (profile.qualification.trim().isNotEmpty) {
      return profile.qualification.trim();
    }
    if (profile.certifications.isNotEmpty) {
      return profile.certifications.join(', ');
    }
    final parts = <String>[];
    if (profile.specialization.trim().isNotEmpty) {
      parts.add(profile.specialization.trim());
    }
    if (profile.superSpecialization.trim().isNotEmpty) {
      parts.add(profile.superSpecialization.trim());
    }
    if (profile.yearsExperience > 0) {
      parts.add('${profile.yearsExperience}+ yrs exp');
    }
    return parts.isEmpty ? 'Registered Medical Practitioner' : parts.join(' · ');
  }

  static String clinicAddressLine(DoctorProfileData profile) {
    final parts = <String>[
      profile.addressLine1,
      profile.addressLine2,
      profile.city,
      profile.pincode,
    ].where((s) => s.trim().isNotEmpty).toList();
    if (parts.isEmpty) return profile.clinicName;
    return parts.join(', ');
  }

  /// Phone and email for prescription PDF / preview headers.
  static String contactDetailsLine(DoctorProfileData profile) {
    final parts = <String>[];
    final mobile = profile.mobile.trim();
    final email = profile.email.trim();
    if (mobile.isNotEmpty) parts.add('Phone: $mobile');
    if (email.isNotEmpty) parts.add('Email: $email');
    return parts.join(' · ');
  }

  static String formatSchedule(DoctorScheduleAvailability schedule) {
    final days = schedule.workingDays.join(', ');
    final buf = StringBuffer('$days · ${schedule.morningStart}–${schedule.morningEnd}');
    if (schedule.eveningEnabled) {
      buf.write(' · ${schedule.eveningStart}–${schedule.eveningEnd}');
    }
    return buf.toString();
  }

  static Future<String> loadConsultationTimings(String doctorId) async {
    DoctorScheduleAvailability? schedule;
    try {
      schedule = await FirestoreService.instance.doctorAvailability.fetch(doctorId, preferCache: true);
    } catch (_) {}
    _timingsCache = formatSchedule(schedule ?? DoctorScheduleAvailability.defaults());
    return _timingsCache!;
  }

  static String get consultationTimings => _timingsCache ?? fallbackTimings;
}
