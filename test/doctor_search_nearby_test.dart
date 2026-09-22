import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/patient/data/registered_doctors_store.dart';
import 'package:medibond/features/patient/profile/data/patient_profile_mock.dart';
import 'package:medibond/features/patient/profile/models/patient_profile_models.dart';
import 'package:medibond/features/patient/search/doctor_search_screen.dart';
import 'package:medibond/features/patient/search/widgets/lab_search_result_tile.dart';

void main() {
  setUp(() {
    PatientProfileMock.reset();
    RegisteredDoctorsStore.instance.markStreamActiveForTesting(true);
  });

  tearDown(() {
    PatientProfileMock.reset();
    RegisteredDoctorsStore.instance.markStreamActiveForTesting(false);
  });

  group('DoctorSearchScreen Nearby Feed Tests', () {
    testWidgets(
        'Empty search shows nearby doctors, labs, ambulances and no "Start your search" idle state',
        (tester) async {
      PatientProfileMock.profileAddress = const PatientAddress(
        city: 'Mumbai',
        pincode: '400001',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: DoctorSearchScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. "Start your search" must NOT be present
      expect(find.text('Start your search'), findsNothing);
      expect(
          find.text('Type a doctor name, lab test, package, or lab.'), findsNothing);

      // 2. Sections: "Doctors near you", "Labs near you", "Ambulances near you"
      expect(find.text('Doctors near you'), findsOneWidget);
      expect(find.text('Labs near you'), findsOneWidget);
      expect(find.text('Ambulances near you'), findsOneWidget);

      // 3. Showing nearby services banner
      expect(find.textContaining('Showing nearby services in Mumbai'), findsOneWidget);

      // 4. "View all" options are present
      expect(find.text('View all'), findsWidgets);
    });

    testWidgets(
        'Typing search query replaces nearby feed with search results, and clearing restores nearby feed',
        (tester) async {
      PatientProfileMock.profileAddress = const PatientAddress(
        city: 'Delhi',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: DoctorSearchScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Doctors near you'), findsOneWidget);

      // Type a query in search bar
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Blood');
      await tester.pump();

      // Nearby sections should yield to query results
      expect(find.text('Doctors near you'), findsNothing);
      expect(find.text('Ambulances near you'), findsNothing);

      // Clear search query
      await tester.enterText(searchField, '');
      await tester.pump();

      // Nearby feed should reappear
      expect(find.text('Doctors near you'), findsOneWidget);
      expect(find.text('Labs near you'), findsOneWidget);
      expect(find.text('Ambulances near you'), findsOneWidget);
    });

    testWidgets('LabSearchResultTile supports ambulance kind', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LabSearchResultTile(
              title: 'City Ambulance',
              subtitle: 'Delhi · BLS · Available',
              kind: LabSearchResultKind.ambulance,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('City Ambulance'), findsOneWidget);
      expect(find.text('Delhi · BLS · Available'), findsOneWidget);
      expect(find.byIcon(Icons.emergency_outlined), findsOneWidget);
    });
  });
}
