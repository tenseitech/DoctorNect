import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase/firestore_query_limits.dart';
import '../../firebase/models/doctor_referral.dart';
import '../supabase_bootstrap.dart';
import 'supabase_patient_profile_repository.dart';

/// Supabase Repository for Doctor Referrals.
/// Replaces Firestore `referrals/{referralId}` queries and streams.
class SupabaseReferralRepository {
  SupabaseReferralRepository._();

  static final SupabaseReferralRepository instance =
      SupabaseReferralRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  Future<void> save(DoctorReferral referral) async {
    if (!SupabaseBootstrap.isReady) return;

    final row = <String, dynamic>{
      'referral_id': referral.referralId,
      'from_doctor_id': referral.fromDoctorId,
      'to_doctor_id': referral.toDoctorId,
      'patient_id': referral.patientId,
      if (referral.appointmentId != null && referral.appointmentId!.isNotEmpty)
        'appointment_id': referral.appointmentId,
      'from_doctor_name': referral.fromDoctorName,
      'to_doctor_name': referral.toDoctorName,
      'to_specialization': referral.toSpecialization,
      'patient_name': referral.patientName,
      'patient_age': referral.patientAge,
      if (referral.reason != null && referral.reason!.isNotEmpty)
        'reason': referral.reason,
      'status': referral.status,
      'created_at': referral.createdAt.toIso8601String(),
    };

    await _client.from('referrals').upsert(row, onConflict: 'referral_id');

    if (referral.patientId.isNotEmpty &&
        SupabasePatientProfileRepository.isRegisteredPatientId(
            referral.patientId)) {
      await SupabasePatientProfileRepository.instance.ensureDoctorPatientLink(
        patientId: referral.patientId,
        doctorId: referral.toDoctorId,
        source: 'referral',
        fromDoctorId: referral.fromDoctorId,
        referralId: referral.referralId,
      );
    }
  }

  Future<DoctorReferral?> fetchById(
    String referralId, {
    bool preferCache = true,
  }) async {
    if (!SupabaseBootstrap.isReady || referralId.isEmpty) return null;

    try {
      final res = await _client
          .from('referrals')
          .select()
          .eq('referral_id', referralId)
          .maybeSingle();

      if (res == null) return null;
      return _fromRow(res);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[SupabaseReferralRepository] fetchById $referralId failed: $e\n$st');
      }
      return null;
    }
  }

  Future<List<DoctorReferral>> fetchSentByDoctor(
    String doctorId, {
    bool preferCache = true,
  }) async {
    return _fetchForDoctorField(
      column: 'from_doctor_id',
      doctorId: doctorId,
    );
  }

  Future<List<DoctorReferral>> fetchReceivedByDoctor(
    String doctorId, {
    bool preferCache = true,
  }) async {
    return _fetchForDoctorField(
      column: 'to_doctor_id',
      doctorId: doctorId,
    );
  }

  Future<List<DoctorReferral>> _fetchForDoctorField({
    required String column,
    required String doctorId,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) return const [];

    try {
      final res = await _client
          .from('referrals')
          .select()
          .eq(column, doctorId)
          .order('created_at', ascending: false)
          .limit(FirestoreQueryLimits.connectionsPage);

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map(_fromRow)
          .whereType<DoctorReferral>()
          .where(
            (r) =>
                r.status == 'sent' ||
                r.status == 'complete' ||
                r.status == 'completed' ||
                r.status == 'accepted',
          )
          .toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[SupabaseReferralRepository] _fetchForDoctorField failed: $e\n$st');
      }
      return const [];
    }
  }

  /// Realtime stream for referrals sent or received by a doctor.
  /// CONVERSION RULE: Multi-column stream -> uses `onPostgresChanges` channel subscription + initial query.
  Stream<List<DoctorReferral>> watchReceivedForDoctor(String doctorId) {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }

    return _client
        .from('referrals')
        .stream(primaryKey: ['referral_id'])
        .eq('to_doctor_id', doctorId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(_fromRow).whereType<DoctorReferral>().toList());
  }

  DoctorReferral? _fromRow(Map<String, dynamic> data) {
    try {
      final referralId = data['referral_id'] as String? ?? '';
      if (referralId.isEmpty) return null;

      DateTime createdAt = DateTime.now();
      if (data['created_at'] != null) {
        createdAt =
            DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now();
      }

      return DoctorReferral(
        referralId: referralId,
        fromDoctorId: data['from_doctor_id'] as String? ?? '',
        fromDoctorName: data['from_doctor_name'] as String? ?? '',
        toDoctorId: data['to_doctor_id'] as String? ?? '',
        toDoctorName: data['to_doctor_name'] as String? ?? '',
        toSpecialization: data['to_specialization'] as String? ?? '',
        patientId: data['patient_id'] as String? ?? '',
        patientName: data['patient_name'] as String? ?? '',
        patientAge: (data['patient_age'] as num?)?.toInt() ?? 0,
        appointmentId: data['appointment_id'] as String?,
        reason: data['reason'] as String?,
        status: data['status'] as String? ?? 'sent',
        createdAt: createdAt,
      );
    } catch (_) {
      return null;
    }
  }
}
