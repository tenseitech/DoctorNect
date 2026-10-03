import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/auth/unified_auth_intro_screen.dart';
import 'package:medibond/features/splash/splash_screen.dart';
import 'package:medibond/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Web Splash Screen Removal Tests', () {
    test('web/index.html has no splash div, spinner markup, or splash CSS', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, isNot(contains('app-loading-splash')));
      expect(html, isNot(contains('splash-container')));
      expect(html, isNot(contains('splash-spinner')));
      expect(html, isNot(contains('Loading Application...')));
      // Bootstrap script is still loaded to initialize Flutter engine
      expect(html, contains('scripts/splash-bootstrap.js'));
    });

    test(
        'web/scripts/splash-bootstrap.js initializes Flutter without splash DOM logic',
        () {
      final js = File('web/scripts/splash-bootstrap.js').readAsStringSync();
      expect(js, isNot(contains('app-loading-splash')));
      expect(js, contains('flutter_bootstrap.js'));
      expect(js, contains('startFlutter()'));
    });

    testWidgets(
      'Web initialScreen path resolves and loads directly into initial screen with no splash screen',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final resolvedScreen = await SplashScreen.resolveInitialScreen(
          initializeFirebase: false,
        );
        expect(resolvedScreen, isA<UnifiedAuthIntroScreen>());

        await tester.pumpWidget(DoctorNectApp(initialScreen: resolvedScreen));
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(SplashScreen), findsNothing);
        expect(find.text('Your Health, Our Priority'), findsNothing);
        expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Mobile (non-web) default path preserves SplashScreen behavior',
      (tester) async {
        await tester.pumpWidget(const DoctorNectApp());
        await tester.pump();

        expect(find.byType(SplashScreen), findsOneWidget);
        expect(find.text('Your Health, Our Priority'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
