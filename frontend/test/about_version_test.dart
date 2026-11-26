import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/patient/profile/about/about_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('About shows the installed app version, not a hard-coded one',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'DoctorNect',
      packageName: 'com.tenseitech.doctornect',
      version: '9.8.7',
      buildNumber: '65',
      buildSignature: '',
    );
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Version 9.8.7 (65)'), findsOneWidget);
    expect(find.textContaining('1.0.1'), findsNothing);
  });
}
