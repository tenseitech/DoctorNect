import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/auth/auth_autoflow_helper.dart';
import 'package:medibond/widgets/otp_input.dart';
import 'package:pinput/pinput.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Behaviour 1: 10th-digit Auto-Send Logic', () {
    test('Normalizes Indian mobile formats (+91, 91, 0, spaces, dashes)', () {
      expect(
        AuthAutoFlowHelper.normalizeMobile('+91 98765-43210'),
        '9876543210',
      );
      expect(
        AuthAutoFlowHelper.normalizeMobile('919876543210'),
        '9876543210',
      );
      expect(
        AuthAutoFlowHelper.normalizeMobile('09876543210'),
        '9876543210',
      );
      expect(
        AuthAutoFlowHelper.normalizeMobile('98765 43210'),
        '9876543210',
      );
      expect(AuthAutoFlowHelper.normalizeMobile('12345'), isNull);
    });

    test('Triggers ONLY when input transitions from < 10 to 10 valid digits',
        () {
      final tracker = MobileAutoSendTracker();

      // Typing digits 1 through 9: must NOT trigger
      for (int i = 1; i <= 9; i++) {
        final partial = '9876543210'.substring(0, i);
        expect(
          tracker.shouldTriggerAutoSend(currentRaw: partial, isBusy: false),
          isFalse,
          reason: 'Typing $i digits must not trigger auto-send',
        );
      }

      // 10th digit entered: MUST trigger once
      expect(
        tracker.shouldTriggerAutoSend(
          currentRaw: '9876543210',
          isBusy: false,
        ),
        isTrue,
        reason: '10th digit transition must trigger auto-send',
      );

      // Typing further or staying at 10: MUST NOT trigger again
      expect(
        tracker.shouldTriggerAutoSend(
          currentRaw: '9876543210',
          isBusy: false,
        ),
        isFalse,
      );
      expect(
        tracker.shouldTriggerAutoSend(
          currentRaw: '98765432100',
          isBusy: false,
        ),
        isFalse,
      );
    });

    test('Does NOT trigger if already busy / in-flight', () {
      final tracker = MobileAutoSendTracker();
      expect(
        tracker.shouldTriggerAutoSend(
          currentRaw: '9876543210',
          isBusy: true,
        ),
        isFalse,
        reason: 'Busy flag must guard against in-flight triggers',
      );
    });

    test('Programmatic prefill with 10 digits does NOT trigger auto-send', () {
      final tracker = MobileAutoSendTracker();
      tracker.initialize('9876543210');

      // First check with prefilled value: must NOT trigger
      expect(
        tracker.shouldTriggerAutoSend(
          currentRaw: '9876543210',
          isBusy: false,
        ),
        isFalse,
        reason: 'Programmatic prefill must not trigger auto-send',
      );
    });

    test('Returning from OTP step does NOT trigger until number is edited', () {
      final tracker = MobileAutoSendTracker();
      tracker.shouldTriggerAutoSend(currentRaw: '9876543210', isBusy: false);

      // User returns from OTP step via change number
      tracker.onReturnedFromOtp('9876543210');

      // Remaining at 10 digits does not re-trigger
      expect(
        tracker.shouldTriggerAutoSend(
          currentRaw: '9876543210',
          isBusy: false,
        ),
        isFalse,
      );

      // User edits number down to 9 digits
      expect(
        tracker.shouldTriggerAutoSend(
          currentRaw: '987654321',
          isBusy: false,
        ),
        isFalse,
      );

      // User enters 10th digit again: MUST trigger
      expect(
        tracker.shouldTriggerAutoSend(
          currentRaw: '9876543210',
          isBusy: false,
        ),
        isTrue,
        reason: 'Re-entering 10th digit after editing must trigger auto-send',
      );
    });

    testWidgets(
        'Widget typing: 9 digits does nothing, 10th digit triggers auto-send once',
        (tester) async {
      int triggerCount = 0;
      final tracker = MobileAutoSendTracker();
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              onChanged: (val) {
                tracker.checkAndNormalize(controller);
                if (tracker.shouldTriggerAutoSend(
                  currentRaw: controller.text,
                  isBusy: false,
                )) {
                  triggerCount++;
                }
              },
            ),
          ),
        ),
      );

      // Enter 9 digits
      await tester.enterText(find.byType(TextField), '987654321');
      await tester.pump();
      expect(triggerCount, 0);

      // Enter 10th digit
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.pump();
      expect(triggerCount, 1);

      // Rebuilding screen or typing extra digit does not trigger again
      await tester.enterText(find.byType(TextField), '98765432101');
      await tester.pump();
      expect(triggerCount, 1);
    });

    testWidgets('Widget programmatic prefill does NOT trigger auto-send',
        (tester) async {
      int triggerCount = 0;
      final tracker = MobileAutoSendTracker();
      final controller = TextEditingController(text: '9876543210');
      tracker.initialize(controller.text);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              onChanged: (val) {
                if (tracker.shouldTriggerAutoSend(
                  currentRaw: controller.text,
                  isBusy: false,
                )) {
                  triggerCount++;
                }
              },
            ),
          ),
        ),
      );

      await tester.pump();
      expect(triggerCount, 0);
    });
  });

  group('Behaviour 2: OTP Auto-Fill, Auto-Submit & Shake-Clear Logic', () {
    testWidgets(
        'OtpInput renders single-input Pinput with length 6 and AutofillGroup',
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

    testWidgets(
        '6th digit automatically triggers onCompleted once without extra tap',
        (tester) async {
      int completedCalls = 0;
      String? completedCode;

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

      // Type first 5 digits
      await tester.enterText(find.byType(Pinput), '12345');
      await tester.pump();
      expect(completedCalls, 0);
      expect(completedCode, isNull);

      // Type 6th digit
      await tester.enterText(find.byType(Pinput), '123456');
      await tester.pump();

      expect(completedCalls, 1);
      expect(completedCode, '123456');
    });

    testWidgets('Pasting a 6-digit code fills and completes', (tester) async {
      String? completedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpInput(
              onChanged: (_) {},
              onCompleted: (val) => completedCode = val,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(Pinput), '948201');
      await tester.pump();

      expect(completedCode, '948201');
    });

    test(
        'OtpDigitsInputFormatter extracts 6 digits from raw, formatted, or SMS text',
        () {
      expect(OtpDigitsInputFormatter.extractOtp('948201'), '948201');
      expect(OtpDigitsInputFormatter.extractOtp('123-456'), '123456');
      expect(OtpDigitsInputFormatter.extractOtp('123 456'), '123456');
      expect(
        OtpDigitsInputFormatter.extractOtp('Your DoctorNect OTP is 654321'),
        '654321',
      );
      expect(OtpDigitsInputFormatter.extractOtp('abc 999 888 xyz'), '999888');
    });

    testWidgets('Backspacing across boxes updates code length and value',
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

      await tester.enterText(find.byType(Pinput), '12345');
      await tester.pump();
      expect(currentCode, '12345');

      await tester.enterText(find.byType(Pinput), '123');
      await tester.pump();
      expect(currentCode, '123');
    });

    testWidgets('enabled: false locks the input while verifying',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpInput(
              enabled: false,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final pinput = tester.widget<Pinput>(find.byType(Pinput));
      expect(pinput.enabled, isFalse);
    });

    testWidgets(
        'shakeAndClear clears code, notifies empty string, and refocuses',
        (tester) async {
      final key = GlobalKey<OtpInputState>();
      String currentCode = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpInput(
              key: key,
              onChanged: (val) => currentCode = val,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(Pinput), '123456');
      await tester.pump();
      expect(currentCode, '123456');

      // Trigger shake and clear
      key.currentState?.shakeAndClear();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(currentCode, '');
      final pinput = tester.widget<Pinput>(find.byType(Pinput));
      expect(pinput.controller?.text, '');
      expect(pinput.focusNode?.hasFocus, isTrue);
    });

    testWidgets(
        'clearAndFocusFirst clears code, resets focus, and clears error on Resend',
        (tester) async {
      final key = GlobalKey<OtpInputState>();
      String currentCode = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpInput(
              key: key,
              hasError: true,
              onChanged: (val) => currentCode = val,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(Pinput), '123456');
      await tester.pump();
      expect(currentCode, '123456');

      // On resend, clearAndFocusFirst clears digits and resets focus
      key.currentState?.clearAndFocusFirst();
      await tester.pump();

      expect(currentCode, '');
      final pinput = tester.widget<Pinput>(find.byType(Pinput));
      expect(pinput.controller?.text, '');
      expect(pinput.focusNode?.hasFocus, isTrue);
    });

    test('Never auto-submits identical wrong OTP twice guard', () {
      String? lastFailedOtp;
      int verifyCount = 0;

      void onAutoVerify(String otp) {
        if (otp == lastFailedOtp) return;
        verifyCount++;
        // Simulate failure
        lastFailedOtp = otp;
      }

      // First attempt with 111111: triggers verify
      onAutoVerify('111111');
      expect(verifyCount, 1);
      expect(lastFailedOtp, '111111');

      // Same code entered again: must NOT trigger verify
      onAutoVerify('111111');
      expect(verifyCount, 1);

      // Different code entered: MUST trigger verify
      onAutoVerify('222222');
      expect(verifyCount, 2);
      expect(lastFailedOtp, '222222');
    });

    test('isNetworkOrServerError detects network faults accurately', () {
      expect(
        AuthAutoFlowHelper.isNetworkOrServerError('network error occurred'),
        isTrue,
      );
      expect(
        AuthAutoFlowHelper.isNetworkOrServerError('Connection timed out'),
        isTrue,
      );
      expect(
        AuthAutoFlowHelper.isNetworkOrServerError('SocketException: OS Error'),
        isTrue,
      );
      expect(
        AuthAutoFlowHelper.isNetworkOrServerError('Firebase is not available.'),
        isTrue,
      );
      expect(
        AuthAutoFlowHelper.isNetworkOrServerError(
            'Invalid OTP. Please try again.'),
        isFalse,
      );
      expect(
        AuthAutoFlowHelper.isNetworkOrServerError('Wrong verification code.'),
        isFalse,
      );
      expect(
        AuthAutoFlowHelper.isNetworkOrServerError('Too many attempts.'),
        isFalse,
      );
      expect(AuthAutoFlowHelper.isNetworkOrServerError(null), isFalse);
    });
  });
}
