import '../../../../core/firebase/firestore_service.dart';
import '../../../../core/data/shared_appointments_store.dart';
import '../../../doctor/clinical/data/clinical_prescription_store.dart';
import '../../../doctor/clinical/data/lab_order_store.dart';
import '../../../doctor/clinical/models/clinical_models.dart';
import '../../../../core/firebase/models/doctor_lab_order.dart';
import 'patient_lab_booking_store.dart';
import '../models/health_record_models.dart';
import '../utils/lab_report_status.dart';

enum MedicalRecordFilter { all, prescription, labTest, bloodTest, tests }

abstract final class MedicalRecordsMapper {
  static List<HealthRecord> mergeForPatient(String patientId) {
    if (patientId.isEmpty) return const [];

    final prescriptions =
        ClinicalPrescriptionStore.instance.forPatient(patientId);
    final labOrders = LabOrderStore.instance.forPatient(patientId);
    final bloodTests = PatientLabBookingStore.instance.forPatient(patientId);

    final records = <HealthRecord>[
      ...prescriptions.map(fromPrescription),
      ...labOrders.map(fromLabOrder),
      ...bloodTests.map(fromLabBooking),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return records;
  }

  static List<HealthRecord> filter(
      List<HealthRecord> records, MedicalRecordFilter filter) {
    return switch (filter) {
      MedicalRecordFilter.all => records,
      MedicalRecordFilter.prescription =>
        records.where((r) => r.prescriptionId != null).toList(),
      MedicalRecordFilter.labTest =>
        records.where((r) => r.labOrderId != null).toList(),
      MedicalRecordFilter.bloodTest =>
        records.where((r) => r.labBookingId != null).toList(),
      MedicalRecordFilter.tests => records
          .where((r) => r.labOrderId != null || r.labBookingId != null)
          .toList(),
    };
  }

  static HealthRecord fromPrescription(PrescriptionDraft draft) {
    final title = draft.primaryDiagnosis.trim().isEmpty
        ? 'Prescription'
        : draft.primaryDiagnosis.trim();

    return HealthRecord(
      id: 'doctor_rx_${draft.prescriptionId}',
      title: title,
      type: HealthRecordType.prescription,
      date: draft.prescriptionDate,
      source: RecordSource.doctorSent,
      fileName: '',
      doctorName: _doctorNameForAppointment(draft.patient.appointmentId),
      notes: draft.chiefComplaint.trim().isEmpty
          ? null
          : draft.chiefComplaint.trim(),
      prescriptionId: draft.prescriptionId,
    );
  }

  static HealthRecord fromLabOrder(DoctorLabOrder order) {
    final tests = order.testNames.where((t) => t.trim().isNotEmpty).toList();
    final title = tests.isEmpty
        ? 'Lab test order'
        : tests.length == 1
            ? tests.first
            : '${tests.first} + ${tests.length - 1} more';

    return HealthRecord(
      id: 'doctor_lab_${order.orderId}',
      title: title,
      type: HealthRecordType.labReport,
      date: order.createdAt,
      source: RecordSource.doctorSent,
      fileName: '',
      doctorName: order.doctorName,
      labName: order.labName,
      notes: _labOrderStatusNote(order),
      labOrderId: order.orderId,
      labReportStatus: LabReportStatus.resolveForOrder(order).kind,
    );
  }

  static HealthRecord fromLabBooking(LabBookingRecord booking) {
    final labLabel = booking.labName?.trim().isNotEmpty == true
        ? booking.labName!.trim()
        : 'Lab';

    return HealthRecord(
      id: 'lab_booking_${booking.bookingId}',
      title: booking.testName,
      type: HealthRecordType.labReport,
      date: booking.dateTime,
      source: RecordSource.labSent,
      fileName: '',
      labName: labLabel,
      notes: _labBookingStatusNote(booking),
      labBookingId: booking.bookingId,
      labReportStatus: LabReportStatus.resolveForBooking(booking).kind,
    );
  }

  static String _labOrderStatusNote(DoctorLabOrder order) =>
      LabReportStatus.resolveForOrder(order).label;

  static String _labBookingStatusNote(LabBookingRecord booking) =>
      LabReportStatus.resolveForBooking(booking).label;

  static String _doctorNameForAppointment(String? appointmentId) {
    if (appointmentId == null || appointmentId.isEmpty) return 'Your doctor';

    for (final appointment
        in SharedAppointmentsStore.instance.patientAppointments()) {
      if (appointment.id == appointmentId ||
          appointment.appointmentId == appointmentId) {
        final name = appointment.doctorName.trim();
        if (name.isNotEmpty) return name.startsWith('Dr.') ? name : 'Dr. $name';
      }
    }
    return 'Your doctor';
  }
}
