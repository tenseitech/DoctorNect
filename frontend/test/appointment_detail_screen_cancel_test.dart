import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/patient/appointments/models/patient_appointment_models.dart';
import 'package:medibond/features/shared/screens/appointment_detail_screen.dart';

void main() {
  testWidgets(
    'bridge cancel with null reason shows as cancelled on the detail screen',
    (tester) async {
      final appointment = PatientAppointment(
        id: 'apt_bridge_cancel_1',
        appointmentId: 'apt_bridge_cancel_1',
        doctorId: 'doc_1',
        doctorName: 'Dr. Jane Smith',
        specialization: 'Cardiology',
        dateTime: DateTime.now().add(const Duration(days: 2)),
        tokenNumber: 5,
        status: PatientBookingStatus.confirmed,
        // Bridge cancel sets doctorStatus = cancelled and cancellationReason = null
        doctorStatus: AppointmentStatus.cancelled,
        cancellationReason: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppointmentDetailScreen(
            isDoctorView: false,
            appointment: appointment,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The status banner in _StatusHeader must render 'Cancelled'
      expect(find.text('Cancelled'), findsOneWidget);
      // It must NOT show 'Confirmed' or 'Upcoming'
      expect(find.text('Confirmed'), findsNothing);
      expect(find.text('Upcoming'), findsNothing);
    },
  );
}
