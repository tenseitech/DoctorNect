import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/demo_auth_config.dart';
import 'package:medibond/core/auth/profile_action_guard.dart';
import 'package:medibond/core/auth/verification_lifecycle.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/session/doctor_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RoleVerificationController.instance.reset();
    DoctorSession.clear();
  });

  tearDown(() {
    RoleVerificationController.instance.reset();
    DoctorSession.clear();
  });

  group('ProfileActionGuard.isAllowed', () {
    test('always allows patient and superAdmin', () {
      expect(ProfileActionGuard.isAllowed(UserType.patient), isTrue);
      expect(ProfileActionGuard.isAllowed(UserType.superAdmin), isTrue);
    });

    test('allows demo doctor phone without verification', () {
      DoctorSession.setDoctor(
        id: DemoAuthConfig.demoDoctorPhone,
        name: 'Demo Doctor',
      );
      expect(ProfileActionGuard.isAllowed(UserType.doctor), isTrue);
    });

    test('returns false when role is unverified and incomplete', () {
      RoleVerificationController.instance.setRoleState(
        UserType.doctor,
        stage: VerificationStage.profileIncomplete,
      );
      expect(ProfileActionGuard.isAllowed(UserType.doctor), isFalse);
    });

    test('returns false when role is submitted for verification', () {
      RoleVerificationController.instance.setRoleState(
        UserType.medicalStore,
        stage: VerificationStage.submittedForVerification,
      );
      expect(ProfileActionGuard.isAllowed(UserType.medicalStore), isFalse);
    });

    test('returns true when role is verified / approved', () {
      RoleVerificationController.instance.setRoleState(
        UserType.lab,
        stage: VerificationStage.verified,
      );
      expect(ProfileActionGuard.isAllowed(UserType.lab), isTrue);
    });
  });

  group('ProfileActionGuard.run', () {
    testWidgets('executes onAllowed immediately when role is allowed', (
      tester,
    ) async {
      RoleVerificationController.instance.setRoleState(
        UserType.doctor,
        stage: VerificationStage.verified,
      );

      var actionExecuted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  ProfileActionGuard.run(context, UserType.doctor, () {
                    actionExecuted = true;
                  });
                },
                child: const Text('Action'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();

      expect(actionExecuted, isTrue);
      expect(find.text('Complete Your Profile'), findsNothing);
    });

    testWidgets(
      'blocks action and displays popup when role is profileIncomplete',
      (tester) async {
        RoleVerificationController.instance.setRoleState(
          UserType.doctor,
          stage: VerificationStage.profileIncomplete,
        );

        var actionExecuted = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ProfileActionGuard.run(context, UserType.doctor, () {
                      actionExecuted = true;
                    });
                  },
                  child: const Text('Action'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Action'));
        await tester.pumpAndSettle();

        expect(actionExecuted, isFalse);
        expect(find.text('Complete Your Profile'), findsOneWidget);
        expect(find.text('Complete Profile'), findsOneWidget);
        expect(find.text('Later'), findsOneWidget);

        // Dismiss popup
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Complete Your Profile'), findsNothing);
      },
    );

    testWidgets(
      'blocks action and displays under review dialog without Complete Profile button when submitted',
      (tester) async {
        RoleVerificationController.instance.setRoleState(
          UserType.ambulance,
          stage: VerificationStage.submittedForVerification,
        );

        var actionExecuted = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ProfileActionGuard.run(context, UserType.ambulance, () {
                      actionExecuted = true;
                    });
                  },
                  child: const Text('Action'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Action'));
        await tester.pumpAndSettle();

        expect(actionExecuted, isFalse);
        expect(find.text('Profile Under Review'), findsOneWidget);
        expect(find.text('Complete Profile'), findsNothing);
        expect(find.text('Understood'), findsOneWidget);

        await tester.tap(find.text('Understood'));
        await tester.pumpAndSettle();

        expect(find.text('Profile Under Review'), findsNothing);
      },
    );
  });

  group('ProfileActionGuard.showOnFirstEntryIfNeeded', () {
    testWidgets('shows popup once on first entry and persists key', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      RoleVerificationController.instance.setRoleState(
        UserType.medicalStore,
        stage: VerificationStage.profileIncomplete,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  ProfileActionGuard.showOnFirstEntryIfNeeded(
                    context,
                    UserType.medicalStore,
                  );
                },
                child: const Text('Entry'),
              );
            },
          ),
        ),
      );

      // First entry
      await tester.tap(find.text('Entry'));
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Profile'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Second entry should NOT show popup
      await tester.tap(find.text('Entry'));
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Profile'), findsNothing);
    });
  });
}
