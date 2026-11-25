import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/registration_otp_service.dart';
import 'package:medibond/core/auth/unified_auth_flow_controller.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';

void main() {
  late List<({String id, UserType role, String otpType})> calls;

  setUp(() {
    calls = [];
    FirebaseBootstrap.isReady = true;
    RegistrationOtpService.debugSendOtpOverride =
        (id, {required role, required otpType}) async {
      calls.add((id: id, role: role, otpType: otpType));
      return (error: null, debugOtp: null);
    };
  });

  tearDown(() {
    RegistrationOtpService.debugSendOtpOverride = null;
    FirebaseBootstrap.isReady = false;
  });

  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    ));
    return ctx;
  }

  for (final preset in <UserType?>[null, UserType.doctor, UserType.ambulance]) {
    testWidgets('phone step always sends one account-agnostic "auth" OTP (preset role: $preset)',
        (tester) async {
      final ctx = await pumpContext(tester);
      for (final number in ['9876543210', '9999900001', '9999900002']) {
        final flow = UnifiedAuthFlowController(role: preset);
        await flow.sendOtp(ctx, number);
        expect(flow.step, UnifiedAuthStep.otp, reason: number);
        expect(flow.matchedRole, isNull, reason: 'no role is decided before OTP verification');
        flow.dispose();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(calls.map((c) => c.otpType).toSet(), {'auth'});
      expect(calls.map((c) => c.role).toSet(), {UserType.patient},
          reason: 'role is decided by the server after verification');
    });
  }

  test('controller has no pre-OTP lookup and no client-side demo routing', () {
    final src = File('lib/core/auth/unified_auth_flow_controller.dart').readAsStringSync();
    expect(src, isNot(contains('resolvePath(')));
    expect(src, isNot(contains('DemoAuthConfig')));
    expect(RegExp(r"otpType: 'registration'").hasMatch(src), isFalse);
  });
}
