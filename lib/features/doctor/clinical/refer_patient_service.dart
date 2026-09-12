import '../../../core/firebase/firestore_service.dart';
import '../../../core/firebase/models/doctor_referral.dart';
import '../../../core/notifications/patient_notification_emitter.dart';
import '../../../core/session/doctor_session.dart';
import '../../patient/data/registered_doctors_store.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../profile/data/doctor_profile_store.dart';
import 'models/clinical_models.dart';

abstract final class ReferPatientService {
  static String _requirePatientId(PatientClinicalContext patient) {
    final patientId = patient.patientId?.trim() ?? '';
    if (patientId.isEmpty) {
      throw StateError(
        'This patient is not registered yet, so the referral cannot be linked to them. Register the patient first.',
      );
    }
    return patientId;
  }

  static Future<DoctorReferral> sendReferral({
    required PatientClinicalContext patient,
    required DoctorListing specialist,
    String? reason,
  }) async {
    final fromDoctorId = DoctorSession.loggedInDoctorId;
    final fromDoctorName = DoctorProfileStore.displayName;
    final patientId = _requirePatientId(patient);

    final referral = DoctorReferral(
      referralId: 'ref_${DateTime.now().microsecondsSinceEpoch}',
      fromDoctorId: fromDoctorId,
      fromDoctorName: fromDoctorName,
      toDoctorId: specialist.id,
      toDoctorName: specialist.name,
      toSpecialization: specialist.specialization,
      patientId: patientId,
      patientName: patient.patientName,
      patientAge: patient.age,
      appointmentId: patient.appointmentId,
      reason: reason?.trim(),
      createdAt: DateTime.now(),
    );

    await FirestoreService.instance.referral.save(referral);

    PatientNotificationEmitter.notifyReferralFromDoctor(
      fromDoctorName: fromDoctorName,
      toDoctorName: specialist.name,
      specialization: specialist.specialization,
    );

    return referral;
  }

  static Future<int> sendPendingReferrals({
    required PatientClinicalContext patient,
    required List<ReferralEntry> referrals,
  }) async {
    var sent = 0;
    final store = RegisteredDoctorsStore.instance;
    for (final entry in referrals) {
      if (entry.sent) continue;
      final specialist = store.findById(entry.doctorId);
      if (specialist == null) continue;
      await sendReferral(
        patient: patient,
        specialist: specialist,
        reason: entry.reason,
      );
      entry.sent = true;
      sent++;
    }
    return sent;
  }
}
