import 'package:medibond/core/firebase/firestore_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/firebase/mappers/appointment_firestore_mapper.dart';
import 'package:medibond/core/invite/doctor_invite_service.dart';
import 'package:medibond/core/invite/pending_doctor_invite_store.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/patient/booking/models/booking_models.dart';
import 'package:medibond/features/patient/profile/models/patient_profile_models.dart';
import 'package:medibond/features/patient/records/models/health_record_models.dart';
import 'package:medibond/features/patient/sharing/patient_sharing_utils.dart';

import 'helpers/booking_fixtures.dart';

HealthRecord _healthRecord(
    {required String id, bool sharedWithDoctors = false}) {
  return HealthRecord(
    id: id,
    title: 'Report $id',
    type: HealthRecordType.labReport,
    date: DateTime(2026, 1, 1),
    source: RecordSource.selfUploaded,
    fileName: '$id.pdf',
    sharedWithDoctors: sharedWithDoctors,
  );
}

Appointment _appointment({String? slotShareReason}) {
  return Appointment(
    id: 'appt1',
    tokenNumber: 1,
    patientName: 'Test Patient',
    age: 30,
    gender: 'Male',
    timeSlot: '10:00 AM',
    appointmentDate: kBookingTestMonday,
    type: AppointmentType.newVisit,
    status: AppointmentStatus.confirmed,
    slotShareReason: slotShareReason,
  );
}

void main() {
  tearDown(() {
    SharedAppointmentsStore.instance.clearForSignOut();
    FirebaseBootstrap.isReady = false;
    PendingDoctorInviteStore.clear();
  });

  group('PatientProfileRepository — clinical sharing gate', () {
    test('isRegisteredPatientId accepts p-prefix ids', () {
      expect(PatientProfileRepository.isRegisteredPatientId('p123'), isTrue);
      expect(PatientProfileRepository.isRegisteredPatientId('P456'), isTrue);
      expect(PatientProfileRepository.isRegisteredPatientId('wi123'), isFalse);
      expect(PatientProfileRepository.isRegisteredPatientId(null), isFalse);
      expect(PatientProfileRepository.isRegisteredPatientId(''), isFalse);
    });

    test('isWalkInPatientId accepts wi-prefix ids', () {
      expect(PatientProfileRepository.isWalkInPatientId('wi99'), isTrue);
      expect(PatientProfileRepository.isWalkInPatientId('WI12'), isTrue);
      expect(PatientProfileRepository.isWalkInPatientId('p99'), isFalse);
    });

    test('sharesRecordsWithDoctors defaults true and respects opt-out', () {
      expect(PatientProfileRepository.sharesRecordsWithDoctors(null), isFalse);
      expect(PatientProfileRepository.sharesRecordsWithDoctors({}), isTrue);
      expect(
        PatientProfileRepository.sharesRecordsWithDoctors(
            {'shareRecordsWithDoctors': false}),
        isFalse,
      );
      expect(
        PatientProfileRepository.sharesRecordsWithDoctors(
            {'shareRecordsWithDoctors': true}),
        isTrue,
      );
    });
  });

  group('PatientSharingUtils — registration invite opt-in', () {
    test('invite link enables shareRecordsWithDoctors', () {
      expect(PatientSharingUtils.deriveInitialShareRecordsWithDoctors('d178'),
          isTrue);
    });

    test('organic signup keeps sharing off until patient opts in', () {
      expect(PatientSharingUtils.deriveInitialShareRecordsWithDoctors(null),
          isFalse);
      expect(PatientSharingUtils.deriveInitialShareRecordsWithDoctors(''),
          isFalse);
    });
  });

  group('PatientSharingUtils — shared time slot', () {
    test('no share reason required on empty slot', () {
      expect(
        PatientSharingUtils.resolveSlotShareReason(
          existingSlotBookings: 0,
          type: SlotShareReasonType.emergency,
          reasonText: '',
        ),
        isNull,
      );
      expect(
        PatientSharingUtils.isSlotShareStepValid(
          slotSelectable: true,
          existingSlotBookings: 0,
          type: null,
          reasonText: '',
        ),
        isTrue,
      );
    });

    test('emergency maps to Emergency label', () {
      expect(
        PatientSharingUtils.resolveSlotShareReason(
          existingSlotBookings: 1,
          type: SlotShareReasonType.emergency,
          reasonText: '',
        ),
        'Emergency',
      );
    });

    test('other reason requires non-empty trimmed text', () {
      expect(
        PatientSharingUtils.isSlotShareStepValid(
          slotSelectable: true,
          existingSlotBookings: 1,
          type: SlotShareReasonType.other,
          reasonText: '   ',
        ),
        isFalse,
      );
      expect(
        PatientSharingUtils.isSlotShareStepValid(
          slotSelectable: true,
          existingSlotBookings: 1,
          type: SlotShareReasonType.other,
          reasonText: 'Family visit',
        ),
        isTrue,
      );
      expect(
        PatientSharingUtils.resolveSlotShareReason(
          existingSlotBookings: 2,
          type: SlotShareReasonType.other,
          reasonText: '  urgent  ',
        ),
        'urgent',
      );
    });

    test('hasSlotCapacityForPatients enforces max three per slot', () {
      expect(
        PatientSharingUtils.hasSlotCapacityForPatients(
          existingSlotBookings: 2,
          patientCount: 1,
        ),
        isTrue,
      );
      expect(
        PatientSharingUtils.hasSlotCapacityForPatients(
          existingSlotBookings: 2,
          patientCount: 2,
        ),
        isFalse,
      );
    });
  });

  group('Appointment.isSharedSlotEmergency', () {
    test('detects emergency case-insensitively', () {
      expect(_appointment(slotShareReason: 'Emergency').isSharedSlotEmergency,
          isTrue);
      expect(
          _appointment(slotShareReason: '  emergency ').isSharedSlotEmergency,
          isTrue);
    });

    test('custom share reason is not emergency', () {
      expect(
          _appointment(slotShareReason: 'Family visit').isSharedSlotEmergency,
          isFalse);
      expect(
          _appointment(slotShareReason: null).isSharedSlotEmergency, isFalse);
    });
  });

  group('HealthRecord sharing filter', () {
    test('filterHealthRecordsSharedWithDoctors keeps only opted-in records',
        () {
      final filtered =
          PatientSharingUtils.filterHealthRecordsSharedWithDoctors([
        _healthRecord(id: 'private', sharedWithDoctors: false),
        _healthRecord(id: 'shared', sharedWithDoctors: true),
      ]);
      expect(filtered.map((r) => r.id), ['shared']);
    });
  });

  group('AppointmentFirestoreMapper — sharing metadata round-trip', () {
    test('slotShareReason, bookedByName, patientRelation survive toMap/fromMap',
        () {
      final original = bookingRecord(
        id: 'rec_share',
        appointmentId: 'APT_SHARE',
        slotLabel: '11:00 AM',
      );
      final enriched = DoctorNectAppointmentRecord(
        id: original.id,
        appointmentId: original.appointmentId,
        doctorId: original.doctorId,
        doctorName: original.doctorName,
        specialization: original.specialization,
        patientName: original.patientName,
        patientAge: original.patientAge,
        patientGender: original.patientGender,
        dateTime: original.dateTime,
        slotLabel: original.slotLabel,
        tokenNumber: original.tokenNumber,
        visitType: original.visitType,
        patientStatus: original.patientStatus,
        doctorStatus: original.doctorStatus,
        bookedByName: 'Account Holder',
        patientRelation: 'Spouse',
        slotShareReason: 'Emergency',
      );

      final map = AppointmentFirestoreMapper.toMap(enriched, patientId: 'p100');
      final restored = AppointmentFirestoreMapper.fromMap('rec_share', map);

      expect(restored, isNotNull);
      expect(restored!.bookedByName, 'Account Holder');
      expect(restored.patientRelation, 'Spouse');
      expect(restored.slotShareReason, 'Emergency');
    });
  });

  group('FamilyProfileMember.relationLabel', () {
    test('maps every FamilyRelation to a display label', () {
      for (final relation in FamilyRelation.values) {
        final member = FamilyProfileMember(
          id: 'f1',
          name: 'Member',
          relation: relation,
          age: 30,
          gender: 'Female',
          bloodGroup: 'O+',
        );
        expect(member.relationLabel, isNotEmpty);
      }
      expect(
        FamilyProfileMember(
          id: 'f1',
          name: 'Member',
          relation: FamilyRelation.spouse,
          age: 30,
          gender: 'Female',
          bloodGroup: 'O+',
        ).relationLabel,
        'Spouse',
      );
    });
  });

  group('Patient invite capture for sharing opt-in', () {
    test('join link captures doctor id used at registration', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978'),
      );
      expect(PendingDoctorInviteStore.pendingDoctorId, 'd1784185736978');
      expect(
        PatientSharingUtils.deriveInitialShareRecordsWithDoctors(
          PendingDoctorInviteStore.pendingDoctorId,
        ),
        isTrue,
      );
    });

    test('invite message mentions doctor name', () {
      final message = DoctorInviteService.inviteMessage(
        doctorName: 'Patel',
        link: 'https://doctornect.com/join?doctor=d1',
      );
      expect(message, contains('Dr. Patel'));
      expect(message, contains('https://doctornect.com/join?doctor=d1'));
    });
  });

  group('SharedAppointmentsStore — shared slot capacity guard', () {
    test('bookingCountForSlot blocks fourth patient on same slot', () {
      SharedAppointmentsStore.instance.mergeFromFirestore([
        bookingRecord(id: 'r1', appointmentId: 'A1', slotLabel: '10:00 AM'),
        bookingRecord(id: 'r2', appointmentId: 'A2', slotLabel: '10:00 AM'),
        bookingRecord(id: 'r3', appointmentId: 'A3', slotLabel: '10:00 AM'),
      ]);

      expect(
        SharedAppointmentsStore.instance.bookingCountForSlot(
          'doc_test',
          kBookingTestMonday,
          '10:00 AM',
        ),
        kMaxPatientsPerTimeSlot,
      );
      expect(
        PatientSharingUtils.hasSlotCapacityForPatients(
          existingSlotBookings: kMaxPatientsPerTimeSlot,
          patientCount: 1,
        ),
        isFalse,
      );
    });
  });
}
