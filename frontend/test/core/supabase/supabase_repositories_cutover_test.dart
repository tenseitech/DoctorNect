import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/config/doctor_patient_cutover_flag.dart';
import 'package:medibond/core/supabase/mappers/appointment_supabase_mapper.dart';
import 'package:medibond/core/supabase/repositories/supabase_appointment_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_doctor_availability_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_doctor_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_family_member_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_health_records_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_patient_profile_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_prescription_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_referral_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_review_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_user_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

void main() {
  group('DoctorPatientCutoverFlag', () {
    tearDown(() {
      DoctorPatientCutoverFlag.debugOverride = null;
    });

    test('defaults to false when uninitialized and no override', () {
      DoctorPatientCutoverFlag.debugOverride = null;
      expect(DoctorPatientCutoverFlag.isEnabled, isFalse);
    });

    test('respects debugOverride true/false', () {
      DoctorPatientCutoverFlag.debugOverride = true;
      expect(DoctorPatientCutoverFlag.isEnabled, isTrue);

      DoctorPatientCutoverFlag.debugOverride = false;
      expect(DoctorPatientCutoverFlag.isEnabled, isFalse);
    });
  });

  group('SupabaseBootstrap Claim Verification', () {
    test('MissingSupabaseClaimException format string', () {
      const ex = MissingSupabaseClaimException('Missing role=authenticated');
      expect(
        ex.toString(),
        'MissingSupabaseClaimException: Missing role=authenticated',
      );
    });
  });

  group('SupabaseDoctorAvailabilityRepository', () {
    test('normalizeTimeLabel standardizes 12-hour AM/PM formatting', () {
      expect(
        SupabaseDoctorAvailabilityRepository.normalizeTimeLabel('09:00 AM'),
        equals('09:00 AM'),
      );
      expect(
        SupabaseDoctorAvailabilityRepository.normalizeTimeLabel('02:30 PM'),
        equals('02:30 PM'),
      );
      expect(
        SupabaseDoctorAvailabilityRepository.normalizeTimeLabel('invalid'),
        equals('invalid'),
      );
    });

    test('fetch returns null when Supabase is not ready', () async {
      SupabaseBootstrap.resetForTesting();
      final res = await SupabaseDoctorAvailabilityRepository.instance.fetch('doc_123');
      expect(res, isNull);
    });
  });

  group('SupabaseUserRepository & DoctorNectUserProfile', () {
    test('fetchProfile returns null when Supabase is not ready', () async {
      SupabaseBootstrap.resetForTesting();
      final user = await SupabaseUserRepository.instance.fetchProfile('user_123');
      expect(user, isNull);
    });

    test('fetchProfile returns null when uid is empty', () async {
      final user = await SupabaseUserRepository.instance.fetchProfile('');
      expect(user, isNull);
    });
  });

  group('SupabaseDoctorRepository', () {
    test('fetchAllDoctors returns empty list when Supabase is not ready', () async {
      SupabaseBootstrap.resetForTesting();
      final docs = await SupabaseDoctorRepository.instance.fetchAllDoctors();
      expect(docs, isEmpty);
    });

    test('isDoctorVerified returns false when Supabase is not ready or doctorId is empty', () async {
      SupabaseBootstrap.resetForTesting();
      final v1 = await SupabaseDoctorRepository.instance.isDoctorVerified('');
      final v2 = await SupabaseDoctorRepository.instance.isDoctorVerified('doc_123');
      expect(v1, isFalse);
      expect(v2, isFalse);
    });

    test('streamAllDoctors returns empty stream when Supabase is not ready', () {
      SupabaseBootstrap.resetForTesting();
      final stream = SupabaseDoctorRepository.instance.streamAllDoctors();
      expect(stream, emitsDone);
    });
  });

  group('SupabasePatientProfileRepository', () {
    test('fetchPatientDocument returns null when Supabase is not ready or patientId empty', () async {
      SupabaseBootstrap.resetForTesting();
      final res1 = await SupabasePatientProfileRepository.instance.fetchPatientDocument('');
      final res2 = await SupabasePatientProfileRepository.instance.fetchPatientDocument('pat_123');
      expect(res1, isNull);
      expect(res2, isNull);
    });
  });

  group('SupabaseFamilyMemberRepository', () {
    test('fetchForPatient returns empty list when Supabase is not ready', () async {
      SupabaseBootstrap.resetForTesting();
      final members = await SupabaseFamilyMemberRepository.instance.fetchForPatient('pat_123');
      expect(members, isEmpty);
    });
  });

  group('SupabaseHealthRecordsRepository', () {
    test('fetchForPatient returns empty list when Supabase is not ready', () async {
      SupabaseBootstrap.resetForTesting();
      final records = await SupabaseHealthRecordsRepository.instance.fetchForPatient('pat_123');
      expect(records, isEmpty);
    });
  });

  group('SupabaseAppointmentRepository & Mapper', () {
    test('fetchForDoctor returns empty list when Supabase is not ready', () async {
      SupabaseBootstrap.resetForTesting();
      final res = await SupabaseAppointmentRepository.instance.fetchForDoctor('doc_123');
      expect(res, isEmpty);
    });

    test('AppointmentSupabaseMapper maps valid row to DoctorNectAppointmentRecord', () {
      final now = DateTime.now();
      final row = <String, dynamic>{
        'appointment_id': 'apt_test_999',
        'doctor_id': 'doc_001',
        'patient_id': 'pat_001',
        'doctor_name': 'Dr. Raman',
        'specialization': 'General',
        'patient_name': 'Aarav Patel',
        'patient_age': 28,
        'patient_gender': 'Male',
        'date_time': now.toIso8601String(),
        'slot_label': '10:00 AM',
        'visit_type': 'newVisit',
        'patient_status': 'confirmed',
        'doctor_status': 'confirmed',
        'token_number': 4,
        'clinic_name': 'Raman Clinic',
        'clinic_address': 'Sector 14',
      };

      final record = AppointmentSupabaseMapper.fromRow(row);
      expect(record, isNotNull);
      expect(record!.id, equals('apt_test_999'));
      expect(record.doctorId, equals('doc_001'));
      expect(record.patientId, equals('pat_001'));
      expect(record.patientName, equals('Aarav Patel'));
      expect(record.slotLabel, equals('10:00 AM'));
      expect(record.tokenNumber, equals(4));
    });

    test('AppointmentSupabaseMapper returns null when essential fields are missing', () {
      expect(AppointmentSupabaseMapper.fromRow({}), isNull);
      expect(
        AppointmentSupabaseMapper.fromRow({'appointment_id': ''}),
        isNull,
      );
    });

    test('watchForDoctor returns empty stream when Supabase is not ready or doctorId is empty', () {
      SupabaseBootstrap.resetForTesting();
      final stream1 = SupabaseAppointmentRepository.instance.watchForDoctor('');
      expect(stream1, emitsDone);

      final stream2 = SupabaseAppointmentRepository.instance.watchForDoctor('doc_123');
      expect(stream2, emitsDone);
    });
  });

  group('SupabasePrescriptionRepository', () {
    test('fetchForDoctor returns empty page when Supabase is not ready', () async {
      SupabaseBootstrap.resetForTesting();
      final page = await SupabasePrescriptionRepository.instance.fetchForDoctor('doc_123');
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('fetchForPatient returns empty list when Supabase is not ready', () async {
      SupabaseBootstrap.resetForTesting();
      final page = await SupabasePrescriptionRepository.instance.fetchForPatient('pat_123');
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('SupabaseReferralRepository', () {
    test('fetchReceivedByDoctor returns empty list when Supabase is not ready', () async {
      SupabaseBootstrap.resetForTesting();
      final res = await SupabaseReferralRepository.instance.fetchReceivedByDoctor('doc_123');
      expect(res, isEmpty);
    });
  });

  group('SupabaseReviewRepository', () {
    test('fetchForDoctor returns empty list when Supabase is not ready', () async {
      SupabaseBootstrap.resetForTesting();
      final res = await SupabaseReviewRepository.instance.fetchForDoctor('doc_123');
      expect(res, isEmpty);
    });

    test('submitReview returns null when parameters are invalid', () async {
      SupabaseBootstrap.resetForTesting();
      final res1 = await SupabaseReviewRepository.instance.submitReview(
        patientId: '',
        doctorId: 'doc_123',
        appointmentId: 'apt_123',
        rating: 5,
        comment: 'Great doctor',
        patientName: 'John',
      );
      expect(res1, isNull);

      final res2 = await SupabaseReviewRepository.instance.submitReview(
        patientId: 'pat_123',
        doctorId: 'doc_123',
        appointmentId: 'apt_123',
        rating: 0, // Invalid rating (< 1)
        comment: 'Great doctor',
        patientName: 'John',
      );
      expect(res2, isNull);
    });
  });
}
