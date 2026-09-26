import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/shared_appointments_store.dart';
import 'mappers/appointment_supabase_mapper.dart';
import 'supabase_bootstrap.dart';
import 'patient_write_guard.dart';

/// Supabase Repository for all Patient-role queries and mutations.
/// Enforces origin tagging (`sync_origin: 'patient_supabase'`) and the
/// two-layer maintenance write guard.
class SupabasePatientRepository {
  SupabasePatientRepository._();
  static final SupabasePatientRepository instance = SupabasePatientRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  // --------------------------------------------------------------------------
  // APPOINTMENTS
  // --------------------------------------------------------------------------

  /// Books a new appointment in Supabase PostgreSQL atomically with slot-level advisory lock
  /// and capacity enforcement (kMaxPatientsPerTimeSlot = 3).
  Future<Map<String, dynamic>> bookAppointment({
    required BuildContext? context,
    required String appointmentId,
    required String doctorId,
    required String patientId,
    required String doctorName,
    required String specialization,
    required String patientName,
    required int patientAge,
    required String patientGender,
    required DateTime dateTime,
    required String slotLabel,
    required String visitType,
    int? tokenNumber,
    String? clinicName,
    String? clinicAddress,
  }) async {
    return PatientWriteGuard.run(
      context: context,
      action: () async {
        final rpcParams = {
          'p_appointment_id': appointmentId,
          'p_doctor_id': doctorId,
          'p_patient_id': patientId,
          'p_doctor_name': doctorName,
          'p_specialization': specialization,
          'p_patient_name': patientName,
          'p_patient_age': patientAge,
          'p_patient_gender': patientGender,
          'p_date_time': dateTime.toIso8601String(),
          'p_slot_label': slotLabel,
          'p_visit_type': visitType,
          'p_token_number': tokenNumber,
          'p_clinic_name': clinicName,
          'p_clinic_address': clinicAddress,
          'p_sync_origin': 'patient_supabase',
        };

        try {
          final res = await _client.rpc(
            'book_appointment_atomic',
            params: rpcParams,
          );
          if (res is Map<String, dynamic>) {
            return res;
          } else if (res is Map) {
            return Map<String, dynamic>.from(res);
          }
        } on PostgrestException catch (e) {
          // Re-throw capacity / duplicate / permission errors cleanly for caller
          if (e.message.contains('SLOT_CAPACITY_REACHED') ||
              e.message.contains('DUPLICATE_PATIENT_BOOKING') ||
              e.code == '23505' ||
              e.code == '42501') {
            rethrow;
          }
          // Fallback to direct upsert only if RPC is missing in an older environment
          if (e.code == '42883' || e.message.contains('function book_appointment_atomic does not exist')) {
            final payload = {
              'appointment_id': appointmentId,
              'doctor_id': doctorId,
              'patient_id': patientId,
              'doctor_name': doctorName,
              'specialization': specialization,
              'patient_name': patientName,
              'patient_age': patientAge,
              'patient_gender': patientGender,
              'date_time': dateTime.toIso8601String(),
              'slot_label': slotLabel,
              'visit_type': visitType,
              'patient_status': 'confirmed',
              'doctor_status': 'pendingRequest',
              'token_number': tokenNumber,
              'clinic_name': clinicName,
              'clinic_address': clinicAddress,
              'sync_origin': 'patient_supabase',
              'updated_at': DateTime.now().toIso8601String(),
            };
            return await _client
                .from('appointments')
                .upsert(payload, onConflict: 'appointment_id')
                .select()
                .single();
          }
          rethrow;
        }

        return <String, dynamic>{};
      },
    );
  }

  /// Fetches all appointments for a patient
  Future<List<Map<String, dynamic>>> fetchAppointments(String patientId) async {
    final res = await _client
        .from('appointments')
        .select()
        .eq('patient_id', patientId)
        .order('date_time', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  /// Converts a Supabase appointment row to a [DoctorNectAppointmentRecord]
  DoctorNectAppointmentRecord? toRecord(Map<String, dynamic> row) =>
      AppointmentSupabaseMapper.fromRow(row);

  /// Cancels an appointment from the patient side
  Future<void> cancelAppointment({
    required BuildContext? context,
    required String appointmentId,
    required String reason,
  }) async {
    await PatientWriteGuard.run(
      context: context,
      action: () async {
        await _client.from('appointments').update({
          'patient_status': 'cancelled',
          'cancellation_reason': reason,
          'sync_origin': 'patient_supabase',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('appointment_id', appointmentId);
      },
    );
  }

  // --------------------------------------------------------------------------
  // PRESCRIPTIONS & HEALTH RECORDS (Reads)
  // --------------------------------------------------------------------------

  /// Fetches all prescriptions for a patient including medicine line items, investigations, and referrals
  Future<List<Map<String, dynamic>>> fetchPrescriptions(String patientId) async {
    final res = await _client
        .from('prescriptions')
        .select('''
          *,
          prescription_medicines(*),
          prescription_investigations(*),
          prescription_referrals(*)
        ''')
        .eq('patient_id', patientId)
        .order('prescription_date', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  // --------------------------------------------------------------------------
  // REVIEWS & FEEDBACK
  // --------------------------------------------------------------------------

  /// Submits a consultation review
  Future<void> submitReview({
    required BuildContext? context,
    required String reviewId,
    required String patientId,
    required String doctorId,
    required String appointmentId,
    required String patientName,
    required int rating,
    required String comment,
  }) async {
    await PatientWriteGuard.run(
      context: context,
      action: () async {
        await _client.from('reviews').upsert({
          'review_id': reviewId,
          'patient_id': patientId,
          'doctor_id': doctorId,
          'appointment_id': appointmentId,
          'patient_name': patientName,
          'rating': rating,
          'comment': comment,
          'sync_origin': 'patient_supabase',
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'patient_id,doctor_id');
      },
    );
  }

  // --------------------------------------------------------------------------
  // PATIENT PROFILE
  // --------------------------------------------------------------------------

  /// Fetches patient profile
  Future<Map<String, dynamic>?> fetchProfile(String patientId) async {
    final res = await _client
        .from('patients')
        .select()
        .eq('patient_id', patientId)
        .maybeSingle();

    return res;
  }

  /// Updates patient profile
  Future<void> updateProfile({
    required BuildContext? context,
    required String patientId,
    required Map<String, dynamic> fields,
  }) async {
    await PatientWriteGuard.run(
      context: context,
      action: () async {
        final payload = {
          ...fields,
          'patient_id': patientId,
          'sync_origin': 'patient_supabase',
          'updated_at': DateTime.now().toIso8601String(),
        };

        await _client
            .from('patients')
            .upsert(payload, onConflict: 'patient_id');
      },
    );
  }

  // --------------------------------------------------------------------------

  /// Fetches all health records for a patient
  Future<List<Map<String, dynamic>>> fetchHealthRecords(String patientId) async {
    final res = await _client
        .from('health_records')
        .select()
        .eq('patient_id', patientId)
        .order('date', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  /// Uploads/creates a health record for a patient (guarded write)
  Future<Map<String, dynamic>> addHealthRecord({
    required BuildContext? context,
    required String recordId,
    required String patientId,
    required String title,
    required String type,
    required DateTime date,
    required String source,
    required String fileName,
    String? doctorName,
    String? labName,
    bool isImage = false,
    String? notes,
    bool sharedWithDoctors = true,
    String fileStorage = 'localOnly',
    String? storageUrl,
  }) async {
    final validFileStorage = (fileStorage == 'cloudUploaded' || fileStorage == 'firebase')
        ? 'cloudUploaded'
        : (fileStorage == 'none' ? 'none' : 'localOnly');

    return PatientWriteGuard.run(
      context: context,
      action: () async {
        final payload = {
          'record_id': recordId,
          'patient_id': patientId,
          'title': title,
          'type': type,
          'date': date.toIso8601String(),
          'source': source,
          'file_name': fileName,
          'doctor_name': doctorName,
          'lab_name': labName,
          'is_image': isImage,
          'notes': notes,
          'shared_with_doctors': sharedWithDoctors,
          'file_storage': validFileStorage,
          'storage_url': storageUrl,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };

        final res = await _client
            .from('health_records')
            .upsert(payload, onConflict: 'record_id')
            .select()
            .single();

        return res;
      },
    );
  }
}
