import 'package:medibond/core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/firebase/models/doctor_availability.dart';
import 'package:medibond/features/patient/appointments/data/patient_appointment_filters.dart';
import 'package:medibond/features/patient/booking/models/booking_models.dart';
import 'package:medibond/features/patient/booking/utils/booking_flow_helpers.dart';

import 'helpers/booking_fixtures.dart';

void main() {
  setUp(() {
    FirebaseBootstrap.isReady = false;
  });

  tearDown(() {
    SharedAppointmentsStore.instance.clearForSignOut();
    FirebaseBootstrap.isReady = false;
    BookingFlowHelpers.debugReset();
  });

  group('booking_models — slot time', () {
    test('isSlotTimeInPast treats yesterday as past', () {
      final ref = DateTime(2026, 7, 28, 12, 0);
      expect(
        isSlotTimeInPast(DateTime(2026, 7, 27), '10:00 AM', ref),
        isTrue,
      );
    });

    test('isSlotTimeInPast treats tomorrow as not past', () {
      final ref = DateTime(2026, 7, 28, 12, 0);
      expect(
        isSlotTimeInPast(DateTime(2026, 7, 29), '10:00 AM', ref),
        isFalse,
      );
    });

    test('isSlotTimeInPast compares today against slot start', () {
      final day = DateTime(2026, 7, 28);
      expect(isSlotTimeInPast(day, '10:00 AM', DateTime(2026, 7, 28, 9, 30)), isFalse);
      expect(isSlotTimeInPast(day, '10:00 AM', DateTime(2026, 7, 28, 10, 0)), isTrue);
      expect(isSlotTimeInPast(day, '10:00 AM', DateTime(2026, 7, 28, 10, 1)), isTrue);
    });

    test('formatSlotTimeLabel and parseSlotTimeLabel round-trip', () {
      const time = TimeOfDay(hour: 10, minute: 30);
      final label = formatSlotTimeLabel(time);
      expect(label, '10:30 AM');

      final parsed = parseSlotTimeLabel(label);
      expect(parsed?.hour, 10);
      expect(parsed?.minute, 30);
    });

    test('parseSlotTimeLabel rejects invalid input', () {
      expect(parseSlotTimeLabel(null), isNull);
      expect(parseSlotTimeLabel(''), isNull);
      expect(parseSlotTimeLabel('invalid'), isNull);
    });

    test('slotLabelsMatch treats equivalent labels as equal', () {
      expect(slotLabelsMatch('10:00 AM', '10:00 AM'), isTrue);
      expect(
        slotLabelsMatch('10:00 AM', '10:00 am'),
        slotLabelsMatch('10:00 am', '10:00 am'),
      );
      expect(slotLabelsMatch('10:00 AM', '11:00 AM'), isFalse);
    });

    test('matchSlotForTime prefers exact label match', () {
      final slots = [
        sampleSlot(label: '10:00 AM'),
        sampleSlot(label: '10:15 AM'),
      ];
      final match = matchSlotForTime(slots, const TimeOfDay(hour: 10, minute: 0));
      expect(match?.label, '10:00 AM');
    });

    test('matchSlotForTime picks nearest slot when no exact match', () {
      final slots = [
        sampleSlot(label: '10:00 AM'),
        sampleSlot(label: '10:15 AM'),
      ];
      final match = matchSlotForTime(slots, const TimeOfDay(hour: 10, minute: 7));
      expect(match?.label, '10:00 AM');
    });
  });

  group('TimeSlot capacity semantics', () {
    test('isFull at capacity limit', () {
      expect(sampleSlot(bookingCount: 2).isFull, isFalse);
      expect(sampleSlot(bookingCount: 3).isFull, isTrue);
    });

    test('requiresShareReason when slot is partially filled', () {
      expect(sampleSlot(bookingCount: 0).requiresShareReason, isFalse);
      expect(sampleSlot(bookingCount: 1).requiresShareReason, isTrue);
      expect(sampleSlot(bookingCount: 2).requiresShareReason, isTrue);
      expect(sampleSlot(bookingCount: 3).requiresShareReason, isFalse);
    });

    test('remainingCapacity subtracts booking count from max', () {
      expect(sampleSlot(bookingCount: 1).remainingCapacity, 2);
      expect(sampleSlot(bookingCount: 3).remainingCapacity, 0);
    });

    test('isSelectable only when status is available', () {
      expect(sampleSlot(status: SlotStatus.available).isSelectable, isTrue);
      expect(sampleSlot(status: SlotStatus.booked).isSelectable, isFalse);
    });
  });

  group('DoctorScheduleAvailabilityRepository — unavailability', () {
    final schedule = DoctorScheduleAvailability.defaults();

    test('weekly off returns reason', () {
      final saturday = DateTime(2026, 8, 1);
      final reason = FirestoreService.instance.doctorAvailability.unavailabilityReason(
        schedule,
        saturday,
      );
      expect(reason, contains('weekly off'));
    });

    test('blocked date returns holiday reason', () {
      final blockedDay = DateTime(2026, 8, 4);
      final custom = schedule.copyWith(
        blockedDates: {blockedDay},
      );
      final reason = FirestoreService.instance.doctorAvailability.unavailabilityReason(
        custom,
        blockedDay,
      );
      expect(reason, contains('holiday'));
    });

    test('leave range returns leave reason', () {
      final leaveDay = DateTime(2026, 8, 5);
      final custom = schedule.copyWith(
        leaveStart: DateTime(2026, 8, 4),
        leaveEnd: DateTime(2026, 8, 6),
      );
      final reason = FirestoreService.instance.doctorAvailability.unavailabilityReason(
        custom,
        leaveDay,
      );
      expect(reason, contains('leave'));
    });

    test('bookable weekday has no reason', () {
      expect(
        FirestoreService.instance.doctorAvailability.unavailabilityReason(
          schedule,
          kBookingTestMonday,
        ),
        isNull,
      );
      expect(
        FirestoreService.instance.doctorAvailability.isUnavailableDay(
          schedule,
          kBookingTestMonday,
        ),
        isFalse,
      );
    });
  });

  group('FirestoreService.instance.doctorAvailability.normalizeTimeLabel', () {
    test('parse and format is idempotent for slot keys', () {
      final normalized = DoctorAvailabilityRepository.normalizeTimeLabel('10:00 AM');
      expect(normalized, isNotEmpty);
      expect(DoctorAvailabilityRepository.normalizeTimeLabel(normalized), normalized);
      expect(
        DoctorAvailabilityRepository.normalizeTimeLabel(' 10:00 AM '),
        normalized,
      );
    });
  });

  group('FirestoreService.instance.doctorAvailability.slotsForDate', () {
    test('generates morning and evening slots on a working day', () async {
      final slots = await FirestoreService.instance.doctorAvailability.slotsForDate(
        doctorId: 'doc_test',
        date: kBookingTestMonday,
        existingAppointments: const [],
        referenceTime: DateTime(kBookingTestMonday.year, kBookingTestMonday.month, kBookingTestMonday.day, 8, 0),
      );

      expect(slots, isNotEmpty);
      expect(slots.first.label, '09:00 AM');
      expect(slots.any((s) => s.label == '04:00 PM'), isTrue);
    });

    test('marks slot booked when three patients already share it', () async {
      final existing = List.generate(
        3,
        (i) => bookingRecord(
          id: 'rec_$i',
          appointmentId: 'APT$i',
          tokenNumber: i + 1,
          slotLabel: '10:00 AM',
        ),
      );

      final slots = await FirestoreService.instance.doctorAvailability.slotsForDate(
        doctorId: 'doc_test',
        date: kBookingTestMonday,
        existingAppointments: existing,
        referenceTime: DateTime(kBookingTestMonday.year, kBookingTestMonday.month, kBookingTestMonday.day, 8, 0),
      );

      final tenAm = slots.firstWhere((s) => s.label == '10:00 AM');
      expect(tenAm.bookingCount, 3);
      expect(tenAm.status, SlotStatus.booked);
      expect(tenAm.isFull, isTrue);
    });

    test('partial slot shows booking count but stays available', () async {
      final existing = [
        bookingRecord(id: 'rec1', slotLabel: '10:00 AM'),
      ];

      final slots = await FirestoreService.instance.doctorAvailability.slotsForDate(
        doctorId: 'doc_test',
        date: kBookingTestMonday,
        existingAppointments: existing,
        referenceTime: DateTime(kBookingTestMonday.year, kBookingTestMonday.month, kBookingTestMonday.day, 8, 0),
      );

      final tenAm = slots.firstWhere((s) => s.label == '10:00 AM');
      expect(tenAm.bookingCount, 1);
      expect(tenAm.status, SlotStatus.available);
      expect(tenAm.requiresShareReason, isTrue);
    });

    test('returns empty list on weekly off', () async {
      final slots = await FirestoreService.instance.doctorAvailability.slotsForDate(
        doctorId: 'doc_test',
        date: DateTime(2026, 8, 1),
        existingAppointments: const [],
        referenceTime: DateTime(2026, 8, 1, 8, 0),
      );
      expect(slots, isEmpty);
    });
  });

  group('SharedAppointmentsStore — slot counting and tokens', () {
    test('bookingCountForSlot counts non-cancelled same-slot bookings', () {
      SharedAppointmentsStore.instance.mergeFromFirestore([
        bookingRecord(id: 'rec1', appointmentId: 'APT1', slotLabel: '10:00 AM'),
        bookingRecord(id: 'rec2', appointmentId: 'APT2', slotLabel: '10:00 AM'),
        bookingRecord(
          id: 'rec3',
          appointmentId: 'APT3',
          slotLabel: '11:00 AM',
        ),
      ]);

      expect(
        SharedAppointmentsStore.instance.bookingCountForSlot(
          'doc_test',
          kBookingTestMonday,
          '10:00 AM',
        ),
        2,
      );
    });

    test('bookingCountForSlot excludes cancelled records', () {
      SharedAppointmentsStore.instance.mergeFromFirestore([
        bookingRecord(id: 'rec1', slotLabel: '10:00 AM'),
        bookingRecord(
          id: 'rec2',
          appointmentId: 'APT2',
          slotLabel: '10:00 AM',
          cancellationReason: 'Patient cancelled',
        ),
      ]);

      expect(
        SharedAppointmentsStore.instance.bookingCountForSlot(
          'doc_test',
          kBookingTestMonday,
          '10:00 AM',
        ),
        1,
      );
    });

    test('nextTokenNumberForDoctorOnDate increments per doctor per day', () {
      SharedAppointmentsStore.instance.mergeFromFirestore([
        bookingRecord(id: 'rec1', tokenNumber: 1),
        bookingRecord(id: 'rec2', appointmentId: 'APT2', tokenNumber: 3),
      ]);

      expect(
        SharedAppointmentsStore.instance.nextTokenNumberForDoctorOnDate(
          'doc_test',
          kBookingTestMonday,
        ),
        4,
      );
      expect(
        SharedAppointmentsStore.instance.nextTokenNumberForDoctorOnDate(
          'other_doc',
          kBookingTestMonday,
        ),
        1,
      );
    });
  });

  group('PatientAppointmentFilters', () {
    test('upcoming includes future non-cancelled appointments', () {
      final future = DateTime.now().add(const Duration(days: 2));
      final upcoming = PatientAppointmentFilters.upcoming([
        patientAppointment(id: 'a1', dateTime: future),
        patientAppointment(
          id: 'a2',
          dateTime: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ]);
      expect(upcoming.map((a) => a.id), ['a1']);
    });

    test('completed includes past non-cancelled appointments', () {
      final past = DateTime.now().subtract(const Duration(days: 2));
      final completed = PatientAppointmentFilters.completed([
        patientAppointment(id: 'a1', dateTime: past),
        patientAppointment(
          id: 'a2',
          dateTime: DateTime.now().add(const Duration(days: 2)),
        ),
      ]);
      expect(completed.map((a) => a.id), ['a1']);
    });

    test('cancelled isolates cancelled appointments', () {
      final cancelled = PatientAppointmentFilters.cancelled([
        patientAppointment(
          id: 'a1',
          dateTime: DateTime.now().add(const Duration(days: 1)),
          cancellationReason: 'No show',
        ),
        patientAppointment(
          id: 'a2',
          dateTime: DateTime.now().add(const Duration(days: 1)),
        ),
      ]);
      expect(cancelled.map((a) => a.id), ['a1']);
    });
  });

  group('Issue #16 regressions — booking confirm guards', () {
    test('resolvePatientGender accepts Male, Female, Other and legacy codes', () {
      expect(BookingFlowHelpers.resolvePatientGender('Male'), 'Male');
      expect(BookingFlowHelpers.resolvePatientGender('Female'), 'Female');
      expect(BookingFlowHelpers.resolvePatientGender('Other'), 'Other');
      expect(BookingFlowHelpers.resolvePatientGender('M'), 'Male');
      expect(BookingFlowHelpers.resolvePatientGender('F'), 'Female');
      expect(BookingFlowHelpers.resolvePatientGender('O'), 'Other');
      expect(BookingFlowHelpers.resolvePatientGender('female'), 'Female');
    });

    test('resolvePatientGender rejects empty and unknown values', () {
      expect(BookingFlowHelpers.resolvePatientGender(''), isNull);
      expect(BookingFlowHelpers.resolvePatientGender('Unknown'), isNull);
      expect(BookingFlowHelpers.resolvePatientGender('Non-binary'), isNull);
    });

    test('newAppointmentId uses Firestore auto-ids, not legacy APT prefix', () {
      final firestore = FakeFirebaseFirestore();
      BookingFlowHelpers.debugAppointmentsCollection =
          firestore.collection('appointments');

      final ids = List.generate(
        25,
        (_) => BookingFlowHelpers.newAppointmentId(),
      );

      expect(ids.toSet().length, 25);
      for (final id in ids) {
        expect(BookingFlowHelpers.isLegacyAppointmentId(id), isFalse);
        expect(id.length, greaterThan(10));
      }
      expect(BookingFlowHelpers.isLegacyAppointmentId('APT12345'), isTrue);
    });
  });
}
