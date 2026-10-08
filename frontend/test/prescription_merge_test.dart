import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/doctor/clinical/data/clinical_prescription_store.dart';
import 'package:medibond/features/doctor/clinical/models/clinical_models.dart';

void main() {
  PrescriptionDraft row(String id, String diagnosis) {
    return PrescriptionDraft(
      patient: const PatientClinicalContext(patientName: 'A', age: 40),
      prescriptionId: id,
    )..primaryDiagnosis = diagnosis;
  }

  test('Firestore prescription wins when Supabase has only part of the chart', () {
    final merged = ClinicalPrescriptionStore.mergeByIdFirestoreWins(
      [row('rx-1', 'supabase-partial')],
      [
        row('rx-1', 'firestore-full'),
        row('rx-2', 'firestore-only'),
      ],
    );
    final byId = {for (final item in merged) item.prescriptionId: item};
    expect(byId.keys, containsAll(['rx-1', 'rx-2']));
    expect(byId['rx-1']!.primaryDiagnosis, 'firestore-full');
    expect(byId['rx-2']!.primaryDiagnosis, 'firestore-only');
  });
}
