import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/patient_details_guard.dart';
import 'package:medibond/core/constants/app_constants.dart';
import 'package:medibond/features/patient/profile/data/patient_profile_mock.dart';

void main() {
  setUp(() {
    PatientProfileMock.reset();
  });

  tearDown(() {
    PatientProfileMock.reset();
  });

  group('PatientDetailsGuard.hasRequiredDetails', () {
    test('returns false when age is 0 and gender is empty', () {
      PatientProfileMock.profile.age = 0;
      PatientProfileMock.profile.gender = '';
      expect(PatientDetailsGuard.hasRequiredDetails(), isFalse);
    });

    test('returns false when age is set but gender is empty', () {
      PatientProfileMock.profile.age = 28;
      PatientProfileMock.profile.gender = '';
      expect(PatientDetailsGuard.hasRequiredDetails(), isFalse);
    });

    test('returns false when gender is set but age is 0 or negative', () {
      PatientProfileMock.profile.age = 0;
      PatientProfileMock.profile.gender = 'Male';
      expect(PatientDetailsGuard.hasRequiredDetails(), isFalse);

      PatientProfileMock.profile.age = -5;
      expect(PatientDetailsGuard.hasRequiredDetails(), isFalse);
    });

    test('returns false when age is out of bounds (> 120)', () {
      PatientProfileMock.profile.age = 121;
      PatientProfileMock.profile.gender = 'Female';
      expect(PatientDetailsGuard.hasRequiredDetails(), isFalse);
    });

    test('returns true when age is between 1 and 120 and gender is valid', () {
      PatientProfileMock.profile.age = 1;
      PatientProfileMock.profile.gender = 'Female';
      expect(PatientDetailsGuard.hasRequiredDetails(), isTrue);

      PatientProfileMock.profile.age = 28;
      PatientProfileMock.profile.gender = 'Male';
      expect(PatientDetailsGuard.hasRequiredDetails(), isTrue);

      PatientProfileMock.profile.age = 120;
      PatientProfileMock.profile.gender = 'Other';
      expect(PatientDetailsGuard.hasRequiredDetails(), isTrue);
    });

    test('normalizes legacy gender strings like M, F, male, female', () {
      PatientProfileMock.profile.age = 30;
      PatientProfileMock.profile.gender = 'male';
      expect(PatientDetailsGuard.hasRequiredDetails(), isTrue);

      PatientProfileMock.profile.gender = 'F';
      expect(PatientDetailsGuard.hasRequiredDetails(), isTrue);

      PatientProfileMock.profile.gender = 'Unknown';
      expect(PatientDetailsGuard.hasRequiredDetails(), isFalse);
    });
  });

  group('PatientDetailsGuard.run execution', () {
    testWidgets('executes onAllowed immediately when details already present', (
      tester,
    ) async {
      PatientProfileMock.profile.age = 25;
      PatientProfileMock.profile.gender = 'Male';

      bool allowedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PatientDetailsGuard.run(context, () {
                  allowedCalled = true;
                }),
                child: const Text('Book'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Book'));
      await tester.pump();

      expect(allowedCalled, isTrue);
      expect(find.byType(PatientDetailsSheet), findsNothing);
    });

    testWidgets('opens sheet and blocks until user provides age and gender', (
      tester,
    ) async {
      PatientProfileMock.profile.age = 0;
      PatientProfileMock.profile.gender = '';

      bool allowedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PatientDetailsGuard.run(context, () {
                  allowedCalled = true;
                }),
                child: const Text('Book'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();

      expect(find.byType(PatientDetailsSheet), findsOneWidget);
      expect(find.text('Patient Details'), findsOneWidget);
      expect(allowedCalled, isFalse);

      // Attempt to save without entering details
      await tester.tap(find.text('Save & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your age'), findsOneWidget);
      expect(find.text('Please select your gender'), findsOneWidget);
      expect(allowedCalled, isFalse);

      // Enter invalid age
      await tester.enterText(find.byType(TextFormField), '150');
      await tester.tap(find.text('Save & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid age (1-120)'), findsOneWidget);

      // Enter valid age and select gender
      await tester.enterText(find.byType(TextFormField), '27');
      await tester.tap(find.text('Female'));
      await tester.pumpAndSettle();

      // Tap Save & Continue
      await tester.tap(find.text('Save & Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(PatientDetailsSheet), findsNothing);
      expect(allowedCalled, isTrue);
      expect(PatientProfileMock.profile.age, equals(27));
      expect(PatientProfileMock.profile.gender, equals('Female'));
    });

    testWidgets('cancelling sheet does not execute onAllowed', (
      tester,
    ) async {
      PatientProfileMock.profile.age = 0;
      PatientProfileMock.profile.gender = '';

      bool allowedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PatientDetailsGuard.run(context, () {
                  allowedCalled = true;
                }),
                child: const Text('Book'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();

      expect(find.byType(PatientDetailsSheet), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(PatientDetailsSheet), findsNothing);
      expect(allowedCalled, isFalse);
    });
  });

  group('Safe Null/Unset Age and Gender Display Fallbacks', () {
    test('AppConstants.patientGenderLabel returns fallback when empty or null',
        () {
      expect(
        AppConstants.patientGenderLabel(null, fallback: 'Not provided'),
        equals('Not provided'),
      );
      expect(
        AppConstants.patientGenderLabel('', fallback: 'Not provided'),
        equals('Not provided'),
      );
      expect(
        AppConstants.patientGenderLabel('Male', fallback: 'Not provided'),
        equals('Male'),
      );
    });
  });
}
