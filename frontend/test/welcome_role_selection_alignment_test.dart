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
      expect(find.byType(RoleCard), findsNWidgets(6));
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Patient'), findsOneWidget);
      expect(find.text('Medical'), findsOneWidget);
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
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Choose your role to continue'), findsOneWidget);
      expect(find.text('Select your role'), findsOneWidget);
      expect(find.byType(RoleCard), findsNWidgets(6));
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
      final roles = [
        'Doctor',
        'Patient',
        'Medical',
        'Pharmacy',
        'Lab',
        'Ambulance'
      ];

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

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Verify UnifiedAuthIntroScreen was pushed
        expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);

        // Pop back to WelcomeScreen for the next role test
        final nav = tester.state<NavigatorState>(find.byType(Navigator));
        nav.pop();
        await tester.pumpAndSettle();
      }
    });
  });
}
