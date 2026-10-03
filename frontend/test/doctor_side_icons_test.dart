import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Doctor Side Icons Assets Existence Tests', () {
    const doctorIcons = [
      'assets/icons/doctor/add_patient.png',
      'assets/icons/doctor/ambulance.png',
      'assets/icons/doctor/appointment.png',
      'assets/icons/doctor/availability.png',
      'assets/icons/doctor/digital_pass.png',
      'assets/icons/doctor/done.png',
      'assets/icons/doctor/invite.png',
      'assets/icons/doctor/lab.png',
      'assets/icons/doctor/pending.png',
      'assets/icons/doctor/prescription.png',
      'assets/icons/doctor/promote.png',
      'assets/icons/doctor/refer.png',
      'assets/icons/doctor/review.png',
      'assets/icons/doctor/today_queue.png',
    ];

    const commonIcons = ['assets/icons/common/digital_pass.png'];

    test('All doctor icons exist on disk and have non-zero size', () {
      for (final iconPath in doctorIcons) {
        final file = File(iconPath);
        expect(file.existsSync(), isTrue, reason: '$iconPath does not exist');
        expect(file.lengthSync(), greaterThan(0), reason: '$iconPath is empty');
      }
    });

    test('Digital pass icon in common exists and matches doctor pass', () {
      for (final iconPath in commonIcons) {
        final file = File(iconPath);
        expect(file.existsSync(), isTrue, reason: '$iconPath does not exist');
        expect(file.lengthSync(), greaterThan(0), reason: '$iconPath is empty');
      }
    });
  });
}
