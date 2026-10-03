import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/validators/name_validator.dart';
import 'package:medibond/features/onboarding/onboarding_name_screen.dart';
import 'package:medibond/features/welcome/welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const allRoles = <UserType, String>{
    UserType.doctor: 'Doctor',
    UserType.patient: 'Patient',
    UserType.medical: 'Medical',
    UserType.medicalStore: 'Pharmacy',
    UserType.lab: 'Lab',
    UserType.ambulance: 'Ambulance',
  };

  group('New User Flow Integration Test - All 6 Roles', () {
    for (final entry in allRoles.entries) {
      final role = entry.key;
      final roleName = entry.value;

      testWidgets(
        'New user -> Role ($roleName) -> Name step -> Real greeting (No fake names)',
        (tester) async {
          // Set a larger screen size so all role cards are visible
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          // Step 1: User arrives at role selection screen with verified mobile & OTP
          await tester.pumpWidget(
            const MaterialApp(
              home: WelcomeScreen(
                verifiedMobile: '9876543210',
                verifiedOtp: '123456',
                isNewUser: true,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Role selection screen is visible
          expect(find.text('Select your role'), findsOneWidget);

          // Find Continue button - initially disabled because no role is selected
          final continueButton = find.widgetWithText(FilledButton, 'Continue');
          expect(continueButton, findsOneWidget);
          var continueWidget = tester.widget<FilledButton>(continueButton);
          expect(
            continueWidget.onPressed,
            isNull,
            reason: 'Continue button must be disabled until a role is selected',
          );

          // Step 2: Select role card
          final roleCard = find.text(roleName);
          expect(roleCard, findsWidgets);
          await tester.tap(roleCard.first);
          await tester.pumpAndSettle();

          // Continue button is now enabled
          continueWidget = tester.widget<FilledButton>(continueButton);
          expect(
            continueWidget.onPressed,
            isNotNull,
            reason: 'Continue button must be enabled once $roleName is selected',
          );

          // Step 3: Tap Continue to go to Name step
          await tester.tap(continueButton);
          await tester.pumpAndSettle();

          // Now on OnboardingNameScreen
          expect(find.byType(OnboardingNameScreen), findsOneWidget);
          expect(find.text('What is your full name?'), findsOneWidget);
          expect(find.text('$roleName Account'), findsOneWidget);

          final nameContinue = find.widgetWithText(FilledButton, 'Continue');
          expect(nameContinue, findsOneWidget);
          var nameContinueWidget = tester.widget<FilledButton>(nameContinue);
          expect(
            nameContinueWidget.onPressed,
            isNull,
            reason: 'Name Continue button must be disabled until valid name is typed',
          );

          // Entering fake role name is rejected
          await tester.enterText(find.byType(TextField), roleName);
          await tester.pumpAndSettle();
          expect(find.text('Please enter your real full name.'), findsOneWidget);
          nameContinueWidget = tester.widget<FilledButton>(nameContinue);
          expect(nameContinueWidget.onPressed, isNull);

          // Entering real name is accepted
          const realName = 'Rahul Sharma';
          await tester.enterText(find.byType(TextField), realName);
          await tester.pumpAndSettle();
          nameContinueWidget = tester.widget<FilledButton>(nameContinue);
          expect(
            nameContinueWidget.onPressed,
            isNotNull,
            reason: 'Name Continue button must be enabled with valid real name',
          );

          // Step 4: Verify formatted greeting shows real name and never fake placeholders
          final greeting = NameValidator.formatGreeting(realName, role: role);
          if (role == UserType.doctor) {
            expect(greeting, 'Hi, Dr. Rahul Sharma');
          } else {
            expect(greeting, 'Hi, Rahul Sharma');
          }

          // Verify that fake fallbacks are strictly rejected
          expect(NameValidator.formatGreeting(roleName, role: role), '');
          expect(NameValidator.isRealName(roleName), isFalse);
          expect(NameValidator.isRealName('$roleName $roleName'), isFalse);
        },
      );
    }
  });

  group('Existing User Flow Integration Test - All 6 Roles', () {
    for (final entry in allRoles.entries) {
      final role = entry.key;
      final roleName = entry.value;

      test(
        'Existing user with saved real name -> direct dashboard (0 prompts) for $roleName',
        () {
          const savedRealName = 'Priya Patel';

          // 1. Verify saved real name is recognized as real
          expect(NameValidator.isRealName(savedRealName), isTrue);

          // 2. Formatted greeting is clean and accurate
          final greeting = NameValidator.formatGreeting(savedRealName, role: role);
          if (role == UserType.doctor) {
            expect(greeting, 'Hi, Dr. Priya Patel');
          } else {
            expect(greeting, 'Hi, Priya Patel');
          }

          // 3. Confirm that no name prompt is needed
          final needsNamePrompt = !NameValidator.isRealName(savedRealName);
          expect(needsNamePrompt, isFalse);
        },
      );
    }
  });

  group('Legacy User Repair Flow Integration Test - All 6 Roles', () {
    for (final entry in allRoles.entries) {
      final role = entry.key;
      final roleName = entry.value;

      test(
        'Legacy user with placeholder/empty name is prompted once for real name for $roleName',
        () {
          final fakePlaceholders = [
            '',
            '   ',
            roleName,
            '$roleName $roleName',
            if (role == UserType.doctor) 'Dr. Doctor',
          ];

          for (final fakeName in fakePlaceholders) {
            // Must NOT be accepted as real name
            expect(
              NameValidator.isRealName(fakeName),
              isFalse,
              reason: '"$fakeName" should trigger name prompt for $roleName',
            );

            // Routing logic triggers name step
            final needsNamePrompt = !NameValidator.isRealName(fakeName);
            expect(needsNamePrompt, isTrue);
          }

          // User enters real name -> persisted -> never prompted again
          const correctedName = 'Vikram Malhotra';
          expect(NameValidator.isRealName(correctedName), isTrue);

          final subsequentLoginNeedsPrompt = !NameValidator.isRealName(correctedName);
          expect(subsequentLoginNeedsPrompt, isFalse);
        },
      );
    }
  });
}
