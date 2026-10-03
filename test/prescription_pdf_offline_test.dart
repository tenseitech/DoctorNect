import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/doctor/clinical/models/clinical_models.dart';
import 'package:medibond/features/doctor/clinical/prescription/prescription_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'PrescriptionPdfService generates valid PDF bytes completely offline with asset fonts',
      () async {
    final draft = PrescriptionDraft(
      patient: const PatientClinicalContext(
        patientName: 'अमित शर्मा (Amit Sharma)',
        age: 32,
        gender: 'Male',
      ),
    );
    draft.doctorName = 'Dr. Rajesh Deshmukh';
    draft.doctorSpecialization = 'Cardiologist';
    draft.clinicName = 'Apex Heart Care Clinic';
    draft.primaryDiagnosis = 'Mild Hypertension - उच्च रक्तदाब';
    draft.medicines.add(
      MedicineEntry()
        ..name = 'Amlodipine 5mg'
        ..dosageAmount = '5'
        ..dosageUnit = 'mg'
        ..instructions = 'After breakfast',
    );

    final bytes = await PrescriptionPdfService.buildPdfBytes(draft);
    expect(bytes, isNotNull);
    expect(bytes.length, greaterThan(1000));
    // Verify standard PDF header magic %PDF-
    expect(bytes[0], equals(0x25)); // %
    expect(bytes[1], equals(0x50)); // P
    expect(bytes[2], equals(0x44)); // D
    expect(bytes[3], equals(0x46)); // F
  });
}
