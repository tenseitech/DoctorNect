import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_theme_controller.dart';
import 'package:medibond/features/auth/unified_auth_intro_screen.dart';
import 'package:medibond/features/welcome/welcome_screen.dart';
import 'package:medibond/widgets/role_card.dart';

void main() {
  group('Welcome Role Selection Alignment Tests', () {
    testWidgets('Renders all 5 role cards in desktop split layout (>= 900px)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: WelcomeScreen(isNewUser: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DoctorNect'), findsAtLeastNWidgets(1));
      expect(
          find.text('One platform for every\nhealthcare role'), findsOneWidget);
      expect(find.text('Select your role'), findsOneWidget);
      expect(find.text('Choose your account type to continue'), findsOneWidget);
      expect(find.byType(RoleCard), findsNWidgets(5));
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Patient'), findsOneWidget);
      expect(find.text('Pharmacy'), findsOneWidget);
      expect(find.text('Lab'), findsOneWidget);
      expect(find.text('Ambulance'), findsOneWidget);
      expect(find.text('Secure & encrypted sign-in'), findsOneWidget);
    });

    testWidgets('Renders role cards in mobile layout (< 900px)',
        (tester) async {
      tester.view.physicalSize = const Size(400, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: WelcomeScreen(isNewUser: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DoctorNect'), findsOneWidget);
      expect(find.text('Who are you joining as?'), findsOneWidget);
      expect(find.text('Pick your role to get started'), findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_MobileRoleTile'),
          findsNWidgets(5));
      expect(find.text('Secure & encrypted sign-in'), findsOneWidget);
    });

    testWidgets('Dark mode toggle updates theme reactively', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: WelcomeScreen(isNewUser: true),
        ),
      );
      await tester.pumpAndSettle();

      final initialDarkMode = AppThemeController.instance.isDarkMode;
      AppThemeController.instance.toggleTheme();
      await tester.pumpAndSettle();

      expect(AppThemeController.instance.isDarkMode, !initialDarkMode);

      // Toggle back to clean up
      AppThemeController.instance.toggleTheme();
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Tapping role card navigates to UnifiedAuthIntroScreen for all roles',
        (tester) async {
      final roles = ['Doctor', 'Patient', 'Pharmacy', 'Lab', 'Ambulance'];

      for (final role in roles) {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          const MaterialApp(
            home: WelcomeScreen(isNewUser: false),
          ),
        );
        await tester.pumpAndSettle();

        // Tap role card then tap Continue button
        await tester.tap(find.text(role));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Continue as $role'));
        await tester.pumpAndSettle();

        // Verify UnifiedAuthIntroScreen was pushed
        expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);

        // Pop back to WelcomeScreen for the next role test
        final nav = tester.state<NavigatorState>(find.byType(Navigator));
        nav.pop();
        await tester.pumpAndSettle();
      }
    });

    testWidgets(
        'Mobile layout renders with zero overflow at 360px and 1.2x text scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.2),
            ),
            child: child!,
          ),
          home: const WelcomeScreen(isNewUser: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('DoctorNect'), findsOneWidget);
      expect(find.text('Who are you joining as?'), findsOneWidget);
      expect(find.text('Pick your role to get started'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Secure & encrypted sign-in'), findsOneWidget);

      // Tap Pharmacy role on mobile
      await tester.tap(find.text('Pharmacy'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Continue as Pharmacy'), findsOneWidget);
    });

    testWidgets(
        'Mobile layout displays all 5 roles on 390x844 and handles selection and continue',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: WelcomeScreen(isNewUser: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Button starts disabled with "Continue"
      expect(find.text('Continue'), findsOneWidget);

      // Tap Doctor
      await tester.tap(find.text('Doctor'));
      await tester.pumpAndSettle();

      expect(find.text('Continue as Doctor'), findsOneWidget);

      // Tap continue and verify navigation
      await tester.tap(find.text('Continue as Doctor'));
      await tester.pumpAndSettle();

      expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);
    });
  });
}
