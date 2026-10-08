import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/layout/responsive_layout.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/auth/patient_registration_screen.dart';
import 'package:medibond/features/auth/unified_auth_intro_screen.dart';
import 'package:medibond/features/auth/unified_mobile_auth_screen.dart';
import 'package:medibond/features/auth/widgets/auth_layout.dart';
import 'package:medibond/features/auth/widgets/unified_auth_mobile_field.dart';
import 'package:medibond/widgets/medibond_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Screen 1 - Welcome Screen Redesign Tests', () {
    testWidgets(
        'Renders navy/teal gradient, logo, carousel, sheet and read-only field',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      // Check header / logo
      expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);

      // Check carousel first tagline
      expect(
        find.text('Instant walk-in and clinic appointment booking'),
        findsOneWidget,
      );

      // Check bottom sheet heading
      expect(
        find.text("Let's get started! Enter your mobile number"),
        findsOneWidget,
      );

      // Check read-only mobile field
      final readOnlyField = find.byType(UnifiedAuthMobileField);
      expect(readOnlyField, findsOneWidget);
      final fieldWidget = tester.widget<UnifiedAuthMobileField>(readOnlyField);
      expect(fieldWidget.readOnly, isTrue);

      // Check "Trouble signing in?" link
      expect(find.text('Trouble signing in?'), findsOneWidget);

      // Check "Continue" button is present in bottom action sheet
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    });

    testWidgets(
        'Tapping Continue button navigates to Screen 2 (UnifiedMobileAuthScreen)',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(UnifiedMobileAuthScreen), findsOneWidget);
      expect(find.text('Enter your mobile number'), findsOneWidget);
    });

    testWidgets(
        'Compact mobile viewport (360x640) renders hero and bottom sheet with Continue button cleanly without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);
      expect(find.text("Let's get started! Enter your mobile number"),
          findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
      expect(find.text('Trouble signing in?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Carousel auto-advances to next slide after 4 seconds',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      expect(
        find.text('Instant walk-in and clinic appointment booking'),
        findsOneWidget,
      );

      // Advance by 4 seconds + animation duration
      await tester.pump(const Duration(seconds: 4, milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        find.text('Find and consult trusted doctors near you'),
        findsOneWidget,
      );
    });

    testWidgets('Tapping "Trouble signing in?" opens help bottom sheet',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Trouble signing in?'));
      await tester.pumpAndSettle();

      expect(find.text("Didn't receive the OTP?"), findsOneWidget);
      expect(find.text('Changed your mobile number?'), findsOneWidget);
      expect(find.text('Contact Support'), findsOneWidget);
    });

    testWidgets(
        'Tapping read-only field navigates to Screen 2 (UnifiedMobileAuthScreen)',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(UnifiedAuthMobileField));
      await tester.pumpAndSettle();

      expect(find.byType(UnifiedMobileAuthScreen), findsOneWidget);
      expect(find.text('Enter your mobile number'), findsOneWidget);
    });

    testWidgets(
        'Web/Desktop layout (>=900px) renders full-screen Row with left carousel (flex 43) and right centered 480px form (flex 57) at 1920x1080',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);
      expect(find.byType(Row), findsWidgets);
      expect(find.byType(UnifiedAuthLoginForm), findsOneWidget);

      final rowFinder = find.ancestor(
        of: find.byType(UnifiedAuthLoginForm),
        matching: find.byType(Row),
      );
      expect(rowFinder, findsWidgets);
      final rowWidget = tester.widget<Row>(rowFinder.first);
      final flexChildren = rowWidget.children.whereType<Expanded>().toList();
      expect(flexChildren.length, equals(2));
      expect(flexChildren[0].flex, equals(43));
      expect(flexChildren[1].flex, equals(57));

      // Find constrained box with maxWidth 480 inside right panel
      final constrainedBox = find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == 480,
      );
      expect(constrainedBox, findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
      expect(find.text('Trouble signing in?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Desktop layout at 1024x768 renders full-screen Row with left panel minWidth >= 380',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);
      expect(find.byType(UnifiedAuthLoginForm), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Desktop layout at 1366x768 renders full-screen Row cleanly without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);
      expect(find.byType(UnifiedAuthLoginForm), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Tablet viewport (<900px breakpoint, e.g. 800x1000) renders mobile layout',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);
      expect(find.byType(UnifiedAuthLoginForm), findsOneWidget);
      expect(find.text("Let's get started! Enter your mobile number"),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Window resize from desktop (1920x1080) to mobile (390x844) and back switches cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(UnifiedAuthLoginForm), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Resize to mobile
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();

      expect(find.byType(UnifiedAuthLoginForm), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Resize back to desktop
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pump();

      expect(find.byType(UnifiedAuthLoginForm), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Desktop layout dark mode toggle switches theme without errors',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      final themeToggle = find.byTooltip('Switch to Light Mode');
      expect(themeToggle, findsOneWidget);

      await tester.tap(themeToggle);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('Screen 2 - Enter Mobile Number Screen Redesign Tests', () {
    testWidgets(
        'Renders AppBar (back + help), title, country code, field, terms and continue button',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedMobileAuthScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // AppBar items
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);

      // Title & description
      expect(find.text('Enter your mobile number'), findsOneWidget);
      expect(
        find.text(
            'We will send a 6-digit verification code to verify your number.'),
        findsOneWidget,
      );

      // Country dial code
      expect(find.text('+91'), findsOneWidget);

      // Terms link
      expect(find.textContaining('Terms & Conditions'), findsOneWidget);

      // Continue button initially disabled
      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(continueButton, findsOneWidget);
      final continueWidget = tester.widget<FilledButton>(continueButton);
      expect(continueWidget.onPressed, isNull);
    });

    testWidgets(
        'Entering 10 digits enables Continue button, < 10 keeps it disabled',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedMobileAuthScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter 9 digits
      final textField = find.byType(TextFormField);
      await tester.enterText(textField, '987654321');
      await tester.pump();

      var continueWidget = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
      expect(continueWidget.onPressed, isNull);

      // Enter 10 digits
      await tester.enterText(textField, '9876543210');
      await tester.pump();

      continueWidget = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
      expect(continueWidget.onPressed, isNotNull);
    });

    testWidgets('Dark mode renders cleanly without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppColors.patientTeal),
          home: const UnifiedMobileAuthScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter your mobile number'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Web/Desktop layout (>=900px) renders full-screen Row with left carousel (flex 43) and right centered 480px form (flex 57) at 1920x1080',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedMobileAuthScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(AuthLayout), findsOneWidget);
      expect(find.byType(AuthBrandingCarousel), findsOneWidget);
      expect(find.text('Enter your mobile number'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);

      final rowFinder = find.ancestor(
        of: find.byType(AuthBrandingCarousel),
        matching: find.byType(Row),
      );
      expect(rowFinder, findsWidgets);

      final rowWidget = tester.widget<Row>(rowFinder.first);
      final flexChildren = rowWidget.children.whereType<Expanded>().toList();
      expect(flexChildren.length, equals(2));
      expect(flexChildren[0].flex, equals(43));
      expect(flexChildren[1].flex, equals(57));

      final constrainedBox = find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == 480,
      );
      expect(constrainedBox, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Desktop layout at 1024x768 renders full-screen Row with left panel >= 380px without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedMobileAuthScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(AuthLayout), findsOneWidget);
      expect(find.byType(AuthBrandingCarousel), findsOneWidget);
      expect(find.text('Enter your mobile number'), findsOneWidget);

      final leftPanelFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints != null &&
            w.constraints!.minWidth >= 380,
      );
      expect(leftPanelFinder, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Desktop layout at 1366x768 renders full-screen Row cleanly without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedMobileAuthScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(AuthLayout), findsOneWidget);
      expect(find.byType(AuthBrandingCarousel), findsOneWidget);
      expect(find.text('Enter your mobile number'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Tablet viewport (<900px breakpoint, e.g. 800x1000) renders mobile layout',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedMobileAuthScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(AuthLayout), findsOneWidget);
      expect(find.byType(AuthBrandingCarousel), findsNothing);
      expect(find.text('Enter your mobile number'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Window resize from desktop (1920x1080) to mobile (390x844) and back switches cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const UnifiedMobileAuthScreen(),
        ),
      );
      await tester.pump();

      expect(find.byType(AuthBrandingCarousel), findsOneWidget);

      // Resize to mobile
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();

      expect(find.byType(AuthBrandingCarousel), findsNothing);
      expect(find.text('Enter your mobile number'), findsOneWidget);

      // Resize back to desktop
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pump();

      expect(find.byType(AuthBrandingCarousel), findsOneWidget);
      expect(find.text('Enter your mobile number'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group(
      'AuthLoginPageShell & Patient Registration Desktop Responsiveness Tests',
      () {
    testWidgets(
        'PatientRegistrationScreen on desktop (1920x1080) renders split layout',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const PatientRegistrationScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Join as Patient'), findsOneWidget);
      expect(find.text('Personal details'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);

      final rowFinder = find.byType(Row);
      expect(rowFinder, findsWidgets);

      final rowWidget = tester.widget<Row>(rowFinder.first);
      final flexChildren = rowWidget.children.whereType<Expanded>().toList();
      expect(flexChildren.length, equals(2));
      expect(flexChildren[0].flex, equals(43));
      expect(flexChildren[1].flex, equals(57));

      final constrainedBox = find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == 480,
      );
      expect(constrainedBox, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'PatientRegistrationScreen at 1024x768 renders cleanly with left panel >= 380px',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const PatientRegistrationScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Join as Patient'), findsOneWidget);
      expect(find.text('Personal details'), findsOneWidget);

      final leftPanelFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints != null &&
            w.constraints!.minWidth >= 380,
      );
      expect(leftPanelFinder, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'PatientRegistrationScreen on mobile (390x844) renders stacked layout',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const PatientRegistrationScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Patient Registration'), findsOneWidget);
      expect(find.text('Personal details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ResponsiveLayout.contentMaxWidth returns 1200 on desktop',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final maxW = ResponsiveLayout.contentMaxWidth(context);
              expect(maxW, equals(1200.0));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
    });
  });

  group('Transparent Logo Mark & Seamless Header Tests', () {
    testWidgets('DoctorNectMark renders transparent asset with soft glow',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppColors.patientTeal),
          home: const Scaffold(
            body: DoctorNectMark(size: 38, softGlow: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DoctorNectMark), findsOneWidget);
      expect(find.byType(Image),
          findsNWidgets(2)); // Glow layer + crisp foreground layer
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'DoctorNectLogo with transparent: true delegates to DoctorNectMark',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: DoctorNectLogo(size: 38, transparent: true, softGlow: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DoctorNectLogo), findsOneWidget);
      expect(find.byType(DoctorNectMark), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'UnifiedAuthIntroScreen top bar renders transparent logo mark and toggles theme cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppColors.patientTeal),
          home: const UnifiedAuthIntroScreen(),
        ),
      );
      await tester.pump();

      // Top bar contains transparent DoctorNectLogo and theme toggle button
      expect(find.byType(DoctorNectLogo), findsOneWidget);
      final logoWidget =
          tester.widget<DoctorNectLogo>(find.byType(DoctorNectLogo));
      expect(logoWidget.transparent, isTrue);
      expect(logoWidget.softGlow, isTrue);

      final themeToggle = find.byTooltip('Switch to Light Mode');
      expect(themeToggle, findsOneWidget);

      // Toggle theme to light mode
      await tester.tap(themeToggle);
      await tester.pump();

      expect(find.byType(DoctorNectLogo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
