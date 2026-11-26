import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/welcome/welcome_screen.dart';

/// QA-04 minimum navigation smoke (widget-level; not device integration_test).
void main() {
  testWidgets('Welcome screen renders role selection without overflow on mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.doctorBlue),
        home: const WelcomeScreen(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Continue'), findsWidgets);
    expect(find.byType(OverflowBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}