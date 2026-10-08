import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';

void main() {
  final store = SharedAppointmentsStore.instance;

  tearDown(() {
    SharedAppointmentsStore.debugBookAppointmentOverride = null;
    SharedAppointmentsStore.debugPersistOverride = null;
    store.mergeFromFirestore(const []);
  });

  test('patient booking calls bookAppointment and does not write the document itself', () async {
    var persisted = false;
    Map<String, dynamic>? payload;
    SharedAppointmentsStore.debugPersistOverride = (_) async {
      persisted = true;
    };
    SharedAppointmentsStore.debugBookAppointmentOverride = (body) async {
      payload = body;
      return {
        'ok': true,
        'appointmentId': 'apt-callable',
        'tokenNumber': 7,
      };
    };

    final booked = await store.bookPatientViaCallable(
      doctorId: 'doc-1',
      doctorName: 'Dr A',
      specialization: 'General',
      date: DateTime(2027, 6, 15),
      slotLabel: '10:00 AM',
      patientName: 'Pat',
      patientAge: 30,
      patientGender: 'Female',
      clinicName: 'Clinic',
      clinicAddress: 'Addr',
      mapsUrl: null,
    );

    expect(persisted, isFalse);
    expect(payload?['doctorId'], 'doc-1');
    expect(payload?.containsKey('appointmentId'), isFalse);
    expect(booked.appointmentId, 'apt-callable');
    expect(booked.tokenNumber, 7);
    expect(
      store.records.any((record) => record.appointmentId == 'apt-callable'),
      isTrue,
    );
  });

  test('booking screen routes new bookings through the callable', () {
    final source = File(
      'lib/features/patient/booking/booking_flow_screen.dart',
    ).readAsStringSync();
    expect(source.contains('bookPatientViaCallable('), isTrue);
    expect(source.contains('addBooking('), isFalse);
  });
}
