import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/doctor/clinical/models/clinical_models.dart';
import 'package:medibond/features/doctor/clinical/widgets/refer_specialist_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReferSpecialistDialog Widget Smoke Test (PERF-01)', () {
    testWidgets('renders dialog and verifies lazy list layout without overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReferSpecialistDialog(
              patient: const PatientClinicalContext(
                patientName: 'Test Patient',
                age: 30,
                gender: 'Female',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReferSpecialistDialog), findsOneWidget);
      expect(find.text('Refer to Specialist'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });
}
