import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  /// Books a new appointment in Supabase PostgreSQL
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

        final res = await _client
            .from('appointments')
            .upsert(payload, onConflict: 'appointment_id')
            .select()
            .single();

        return res;
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

  /// Fetches all prescriptions for a patient including medicine line items
  Future<List<Map<String, dynamic>>> fetchPrescriptions(String patientId) async {
    final res = await _client
        .from('prescriptions')
        .select('*, prescription_medicines(*)')
        .eq('patient_id', patientId)
        .order('created_at', ascending: false);

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
          'sync_origin': 'patient_supabase',
          'updated_at': DateTime.now().toIso8601String(),
        };

        await _client
            .from('patients')
            .update(payload)
            .eq('patient_id', patientId);
      },
    );
  }
}
