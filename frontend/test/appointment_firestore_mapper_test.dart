import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/firebase/mappers/appointment_firestore_mapper.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/patient/appointments/models/patient_appointment_models.dart';

void main() {
  group('AppointmentFirestoreMapper', () {
    test('maps valid appointment document correctly', () {
      final now = DateTime.now();
      final data = <String, dynamic>{
        'appointmentId': 'apt-valid-1',
        'doctorId': 'doc-123',
        'doctorName': 'Dr. Sharma',
        'specialization': 'Cardiology',
        'patientId': 'pat-456',
        'patientName': 'Rahul Verma',
        'patientAge': 32,
        'patientGender': 'Male',
        'dateTime': Timestamp.fromDate(now),
        'slotLabel': '10:00 AM',
        'tokenNumber': 5,
        'visitType': 'newVisit',
        'patientStatus': 'confirmed',
        'doctorStatus': 'confirmed',
      };

      final record = AppointmentFirestoreMapper.fromMap('apt-valid-1', data);
      expect(record, isNotNull);
      expect(record!.id, 'apt-valid-1');
      expect(record.doctorId, 'doc-123');
      expect(record.patientStatus, PatientBookingStatus.confirmed);
      expect(record.doctorStatus, AppointmentStatus.confirmed);
    });

    test('drops unparseable appointment document and logs stable prefix without PII', () {
      final capturedLogs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          capturedLogs.add(message);
        }
      };

      try {
        // 'completed' is an invalid value for PatientBookingStatus (only pending, confirmed exist)
        final unparseableData = <String, dynamic>{
          'appointmentId': 'apt-corrupt-99',
          'doctorId': 'doc-123',
          'doctorName': 'Dr. SecretDoctor',
          'patientName': 'Secret Patient Name',
          'clinicalNotes': 'Private patient medical history',
          'patientStatus': 'completed', // Throws ArgumentError in values.byName
          'doctorStatus': 'completed',
        };

        final record = AppointmentFirestoreMapper.fromMap('apt-corrupt-99', unparseableData);

        // 1. Unparseable record must be dropped (returns null)
        expect(record, isNull);

        // 2. Stable prefix log must be emitted
        expect(
          capturedLogs.any(
            (log) => log.contains('[AppointmentFirestoreMapper.fromMap] Dropping unparseable appointment apt-corrupt-99'),
          ),
          isTrue,
        );

        // 3. Error type must be logged
        expect(
          capturedLogs.any((log) => log.contains('error: ArgumentError')),
          isTrue,
        );

        // 4. Zero PII or sensitive appointment content must be in the log
        for (final log in capturedLogs) {
          expect(log.contains('Secret Patient Name'), isFalse);
          expect(log.contains('Private patient medical history'), isFalse);
          expect(log.contains('Dr. SecretDoctor'), isFalse);
        }
      } finally {
        debugPrint = originalDebugPrint;
      }
    });
  });
}
