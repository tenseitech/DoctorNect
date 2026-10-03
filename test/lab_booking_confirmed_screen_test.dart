import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/features/patient/lab/lab_booking_confirmed_screen.dart';
import 'package:medibond/features/patient/lab/models/lab_models.dart';

void main() {
  testWidgets('LabBookingConfirmedScreen renders without overflow at 360x640 with textScaler 1.3', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final booking = ConfirmedLabBooking(
      bookingId: 'LB-992144',
      testName: 'Complete Blood Count (CBC) with Differential and Platelet Count',
      date: DateTime.now().add(const Duration(days: 1)),
      slotLabel: '09:00 AM - 10:00 AM',
      isHomeCollection: true,
      address: 'Flat 402, Green Meadows Apartment, Shivaji Nagar, Pune 411005',
      awaitingLabApproval: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.doctorBlue),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.3),
          ),
          child: LabBookingConfirmedScreen(booking: booking),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Booking Confirmed!'), findsOneWidget);
    expect(find.text('Booking ID: LB-992144'), findsOneWidget);
  });

  testWidgets('LabBookingConfirmedScreen renders pending state without overflow at 360x640 with textScaler 1.3', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final booking = ConfirmedLabBooking(
      bookingId: 'LB-992145',
      testName: 'Lipid Profile & HbA1c Comprehensive Screening',
      date: DateTime.now().add(const Duration(days: 2)),
      slotLabel: '11:00 AM - 12:00 PM',
      isHomeCollection: false,
      address: 'Dr. Lal PathLabs, FC Road, Deccan Gymkhana, Pune',
      awaitingLabApproval: true,
      labName: 'Dr. Lal PathLabs',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.doctorBlue),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.3),
          ),
          child: LabBookingConfirmedScreen(booking: booking),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Request sent!'), findsOneWidget);
  });
}
