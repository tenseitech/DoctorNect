import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/profile_draft_store.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/validators/name_validator.dart';
import 'package:medibond/features/onboarding/onboarding_name_screen.dart';
import 'package:medibond/features/profile/profile_completion_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NameValidator Tests - Eliminating Fake Names Across All 6 Roles', () {
    test('Rejects invalid or fake names', () {
      expect(NameValidator.isValid(null), isFalse);
      expect(NameValidator.isValid(''), isFalse);
      expect(NameValidator.isValid('   '), isFalse);
      expect(NameValidator.isValid('a'), isFalse); // < 2 characters
      expect(NameValidator.validate('   '), 'Full name is required.');
      expect(NameValidator.validate('a'), 'Full name must be at least 2 characters.');

      // Rejects fake role names for each of the 6 roles
      expect(NameValidator.isRealName('Doctor'), isFalse);
      expect(NameValidator.isRealName('Dr. Doctor'), isFalse);
      expect(NameValidator.isRealName('Doctor Doctor'), isFalse);
      expect(NameValidator.isRealName('Patient'), isFalse);
      expect(NameValidator.isRealName('Patient Patient'), isFalse);
      expect(NameValidator.isRealName('Medical'), isFalse);
      expect(NameValidator.isRealName('Medical Medical'), isFalse);
      expect(NameValidator.isRealName('Pharmacy'), isFalse);
      expect(NameValidator.isRealName('Pharmacy Pharmacy'), isFalse);
      expect(NameValidator.isRealName('Lab'), isFalse);
      expect(NameValidator.isRealName('Lab Lab'), isFalse);
      expect(NameValidator.isRealName('Ambulance'), isFalse);
      expect(NameValidator.isRealName('Ambulance Ambulance'), isFalse);
    });

    test('Accepts valid real names', () {
      expect(NameValidator.isValid('Rahul Sharma'), isTrue);
      expect(NameValidator.isRealName('Rahul Sharma'), isTrue);
      expect(NameValidator.isValid('Dr. Rahul Sharma'), isTrue);
      expect(NameValidator.isRealName('Priya Patel'), isTrue);
      expect(NameValidator.cleanDisplayName('  Ananya Verma  '), 'Ananya Verma');
    });

    test('Formats greetings accurately per role with no fake fallbacks', () {
      // Doctor role
      expect(
        NameValidator.formatGreeting('Rahul Sharma', role: UserType.doctor),
        'Hi, Dr. Rahul Sharma',
      );
      expect(
        NameValidator.formatGreeting('Dr. Rahul Sharma', role: UserType.doctor),
        'Hi, Dr. Rahul Sharma',
      );

      // Patient role
      expect(
        NameValidator.formatGreeting('Rahul Sharma', role: UserType.patient),
        'Hi, Rahul Sharma',
      );

      // Medical / Pharmacy role
      expect(
        NameValidator.formatGreeting('City Care Pharmacy', role: UserType.medicalStore),
        'Hi, City Care Pharmacy',
      );
      expect(
        NameValidator.formatGreeting('City Care Pharmacy', role: UserType.medical),
        'Hi, City Care Pharmacy',
      );

      // Lab role
      expect(
        NameValidator.formatGreeting('Metropolis Lab', role: UserType.lab),
        'Hi, Metropolis Lab',
      );

      // Ambulance role
      expect(
        NameValidator.formatGreeting('Rapid Care Ambulance', role: UserType.ambulance),
        'Hi, Rapid Care Ambulance',
      );

      // Never formats fake names - returns empty string so UI doesn't display "Hi Doctor"
      expect(
        NameValidator.formatGreeting('Doctor', role: UserType.doctor),
        '',
      );
      expect(NameValidator.cleanDisplayName('Doctor'), '');
      expect(NameValidator.cleanDisplayName('Pharmacy'), '');
      expect(NameValidator.cleanDisplayName('Lab'), '');
      expect(NameValidator.cleanDisplayName('Ambulance'), '');
    });
  });

  group('ProfileDraftStore Tests - Draft Persistence Across Modal & Reload', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Saves and restores draft data from storage', () async {
      final draft = {
        'fullName': 'Dr. Vikram Seth',
        'city': 'Bengaluru',
        'specialty': 'Cardiologist',
        'experienceYears': 12,
      };

      await ProfileDraftStore.instance.saveDraft(
        role: UserType.doctor,
        userIdOrPhone: 'test-uid-123',
        data: draft,
      );

      final loaded = await ProfileDraftStore.instance.getDraft(
        role: UserType.doctor,
        userIdOrPhone: 'test-uid-123',
      );
      expect(loaded, isNotNull);
      expect(loaded!['fullName'], 'Dr. Vikram Seth');
      expect(loaded['city'], 'Bengaluru');
      expect(loaded['specialty'], 'Cardiologist');
      expect(loaded['experienceYears'], 12);
    });

    test('Clears draft data upon completion', () async {
      await ProfileDraftStore.instance.saveDraft(
        role: UserType.doctor,
        userIdOrPhone: 'test-uid-456',
        data: {'fullName': 'Aarav'},
      );
      await ProfileDraftStore.instance.clearDraft(
        role: UserType.doctor,
        userIdOrPhone: 'test-uid-456',
      );

      final loaded = await ProfileDraftStore.instance.getDraft(
        role: UserType.doctor,
        userIdOrPhone: 'test-uid-456',
      );
      expect(loaded, isNull);
    });
  });

  group('OnboardingNameScreen Widget Tests', () {
    testWidgets('Continue button is disabled until valid full name is typed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingNameScreen(
            role: UserType.doctor,
            mobileDigits: '9876543210',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('What is your full name?'), findsOneWidget);
      expect(find.text('Doctor Account'), findsOneWidget);

      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(continueButton, findsOneWidget);

      // Initially disabled
      final buttonWidget = tester.widget<FilledButton>(continueButton);
      expect(buttonWidget.onPressed, isNull);

      // Type 1 character (invalid)
      await tester.enterText(find.byType(TextField), 'R');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

      // Type spaces only (invalid)
      await tester.enterText(find.byType(TextField), '    ');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

      // Type fake name 'Doctor' (invalid)
      await tester.enterText(find.byType(TextField), 'Doctor');
      await tester.pumpAndSettle();
      expect(find.text('Please enter your real full name.'), findsOneWidget);
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

      // Type valid real name
      await tester.enterText(find.byType(TextField), 'Dr. Rahul Sharma');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    });

    testWidgets('Works for all 6 roles with proper badge label', (tester) async {
      final roles = [
        (UserType.doctor, 'Doctor Account'),
        (UserType.patient, 'Patient Account'),
        (UserType.medical, 'Medical Account'),
        (UserType.medicalStore, 'Pharmacy Account'),
        (UserType.lab, 'Lab Account'),
        (UserType.ambulance, 'Ambulance Account'),
      ];

      for (final (role, expectedLabel) in roles) {
        await tester.pumpWidget(
          MaterialApp(
            home: OnboardingNameScreen(
              role: role,
              mobileDigits: '9876543210',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(expectedLabel), findsOneWidget);
      }
    });
  });

  group('ProfileCompletionModal Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Renders properly for all 6 roles with X close button preserving data', (tester) async {
      final roles = [
        UserType.doctor,
        UserType.patient,
        UserType.medical,
        UserType.medicalStore,
        UserType.lab,
        UserType.ambulance,
      ];

      for (final role in roles) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ProfileCompletionModal.show(context, role: role),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Open Modal'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Modal is open
        expect(find.byType(ProfileCompletionModal), findsOneWidget);
        expect(find.text('Complete Your Profile'), findsOneWidget);
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);
        expect(find.text('Save & Continue'), findsOneWidget);

        // Tap X close button
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        // Modal closed cleanly without browser alert or crash
        expect(find.byType(ProfileCompletionModal), findsNothing);
      }
    });
  });
}
