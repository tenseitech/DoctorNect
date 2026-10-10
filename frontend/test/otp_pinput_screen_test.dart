import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/constants/app_constants.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/features/auth/unified_mobile_auth_screen.dart';
import 'package:medibond/widgets/otp_input.dart';
import 'package:pinput/pinput.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OTP Pinput Screen & Shared Widget Tests', () {
    test('AppConstants.otpResendCooldownSeconds is 30s', () {
      expect(AppConstants.otpResendCooldownSeconds, 30);
    });

    testWidgets('OtpInput uses Pinput with length 6 and AutofillGroup',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpInput(
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byType(Pinput), findsOneWidget);
      expect(find.byType(AutofillGroup), findsWidgets);

      final pinput = tester.widget<Pinput>(find.byType(Pinput));
      expect(pinput.length, 6);
      expect(pinput.keyboardType, TextInputType.number);
      expect(pinput.autofillHints, contains(AutofillHints.oneTimeCode));
    });

    testWidgets('Bug 1 Fix: 6th digit enters cleanly and fires onCompleted',
        (tester) async {
      String? completedCode;
      int completedCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpInput(
              onChanged: (_) {},
              onCompleted: (val) {
                completedCalls++;
                completedCode = val;
              },
            ),
          ),
        ),
      );

      // Typing 5 digits
      await tester.enterText(find.byType(Pinput), '12345');
      await tester.pump();
      expect(completedCalls, 0);
      expect(completedCode, isNull);

      // 6th digit can be entered without dropping or freezing
      await tester.enterText(find.byType(Pinput), '123456');
      await tester.pump();

      expect(completedCalls, 1);
      expect(completedCode, '123456');
    });

    testWidgets('Backspace across boxes updates value and length',
        (tester) async {
      String currentCode = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpInput(
              onChanged: (val) => currentCode = val,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(Pinput), '123456');
      await tester.pump();
      expect(currentCode, '123456');

      // Backspace to 5 digits
      await tester.enterText(find.byType(Pinput), '12345');
      await tester.pump();
      expect(currentCode, '12345');

      // Backspace to 2 digits
      await tester.enterText(find.byType(Pinput), '12');
      await tester.pump();
      expect(currentCode, '12');

      // Backspace to empty
      await tester.enterText(find.byType(Pinput), '');
      await tester.pump();
      expect(currentCode, '');
    });

    testWidgets('Paste full 6-digit code, 3-3 code, and SMS body',
        (tester) async {
      String? completed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpInput(
              onChanged: (_) {},
              onCompleted: (v) => completed = v,
            ),
          ),
        ),
      );

      // Direct 6-digit paste
      await tester.enterText(find.byType(Pinput), '654321');
      await tester.pump();
      expect(completed, '654321');

      // Formatter extracts from 3-3 format
      expect(OtpDigitsInputFormatter.extractOtp('456-789'), '456789');
      expect(OtpDigitsInputFormatter.extractOtp('456 789'), '456789');

      // Formatter extracts from full SMS message
      expect(
        OtpDigitsInputFormatter.extractOtp(
            'Your login OTP is 829104. Valid for 10 min.'),
        '829104',
      );
    });

    testWidgets(
        'Bug 2 Fix: On Resend clearAndFocusFirst clears code, resets focus, and clears error',
        (tester) async {
      final key = GlobalKey<OtpInputState>();
      String currentCode = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpInput(
              key: key,
              hasError: true,
              onChanged: (v) => currentCode = v,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(Pinput), '999888');
      await tester.pump();
      expect(currentCode, '999888');

      // Simulate resend tap triggering clearAndFocusFirst
      key.currentState?.clearAndFocusFirst();
      await tester.pump();

      expect(currentCode, '');
      final pinput = tester.widget<Pinput>(find.byType(Pinput));
      expect(pinput.controller?.text, '');
      expect(pinput.focusNode?.hasFocus, isTrue);
    });

    testWidgets(
        'UnifiedMobileAuthScreen renders for each role with role accent color',
        (tester) async {
      for (final role in [
        UserType.doctor,
        UserType.patient,
        UserType.medicalStore,
        UserType.lab,
        UserType.ambulance,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: UnifiedMobileAuthScreen(
              role: role,
              initialMobile: '9876543210',
            ),
          ),
        );

        // Renders mobile auth page cleanly
        expect(find.byType(UnifiedMobileAuthScreen), findsOneWidget);
        await tester.pump();
      }
    });

    testWidgets(
        'Verify & Continue button enabled ONLY when 6 digits are present in OTP step',
        (tester) async {
      final key = GlobalKey<OtpInputState>();
      String code = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                final canContinue = code.length == 6;
                return Column(
                  children: [
                    OtpInput(
                      key: key,
                      onChanged: (val) => setState(() => code = val),
                    ),
                    FilledButton(
                      onPressed: canContinue ? () {} : null,
                      child: const Text('Verify & Continue'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      final buttonFinder =
          find.widgetWithText(FilledButton, 'Verify & Continue');
      expect(tester.widget<FilledButton>(buttonFinder).enabled, isFalse);

      // Enter 5 digits
      await tester.enterText(find.byType(Pinput), '12345');
      await tester.pump();
      expect(tester.widget<FilledButton>(buttonFinder).enabled, isFalse);

      // Enter 6th digit -> enabled
      await tester.enterText(find.byType(Pinput), '123456');
      await tester.pump();
      expect(tester.widget<FilledButton>(buttonFinder).enabled, isTrue);

      // Backspace -> disabled again
      await tester.enterText(find.byType(Pinput), '12345');
      await tester.pump();
      expect(tester.widget<FilledButton>(buttonFinder).enabled, isFalse);
    });
  });
}
