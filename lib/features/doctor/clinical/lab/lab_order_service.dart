import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/firebase/models/doctor_lab_order.dart';
import '../../../../core/session/doctor_session.dart';
import '../../profile/data/doctor_profile_store.dart';
import '../data/lab_order_store.dart';
import '../models/clinical_models.dart';

/// Shared lab-order flow for Investigations tab and prescription Send to Lab.
abstract final class LabOrderService {
  static String resolvePatientId(PatientClinicalContext patient) =>
      patient.patientId ??
      ''; // FIXED: never fabricate a PAT-{hash} id; empty means unresolved

  static Future<DoctorLabOrder> sendOrder({
    required PatientClinicalContext patient,
    required List<String> testIds,
    required List<String> testNames,
    String? labId,
    String? labName,
    String? indication,
    String urgency = 'Routine',
    bool fastingRequired = false,
    bool homeCollection = false,
    String source = 'investigations',
  }) async {
    final trimmedNames =
        testNames.map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
    if (trimmedNames.isEmpty) {
      throw ArgumentError('At least one lab test is required');
    }

    final doctorId = DoctorSession.loggedInDoctorId;
    final doctorName = DoctorProfileStore.displayName;
    final patientId = resolvePatientId(patient);
    if (patientId.isEmpty) {
      // FIXED: block the write instead of saving with a fake id the patient can never read
      throw StateError(
        'This patient is not registered yet, so the lab order cannot be linked to them. Register the patient first.',
      );
    }
    final orderId = 'lab_${DateTime.now().microsecondsSinceEpoch}';

    final order = DoctorLabOrder(
      orderId: orderId,
      doctorId: doctorId,
      doctorName: doctorName,
      patientId: patientId,
      patientName: patient.patientName,
      patientAge: patient.age,
      appointmentId: patient.appointmentId,
      testIds: testIds,
      testNames: trimmedNames,
      labId: labId?.trim().isNotEmpty == true
          ? labId!.trim()
          : null, // FIXED: persist labId on the order
      labName: labName?.trim().isNotEmpty == true ? labName!.trim() : null,
      indication:
          indication?.trim().isNotEmpty == true ? indication!.trim() : null,
      urgency: urgency,
      fastingRequired: fastingRequired,
      homeCollection: homeCollection,
      source: source,
      createdAt: DateTime.now(),
    );

    await LabOrderStore.instance.add(
        order); // FIXED: await so a Firestore save failure propagates to the caller

    final appointmentId = patient.appointmentId;
    if (appointmentId != null && appointmentId.isNotEmpty) {
      await SharedAppointmentsStore.instance.appendLabReports(
        recordId: appointmentId,
        reports: trimmedNames,
      );
    }

    return order;
  }
}
