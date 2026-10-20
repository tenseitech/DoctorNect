import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/patient/models/patient_models.dart';
import '../supabase_bootstrap.dart';

/// Supabase Repository for Doctor Directory, Verification, and Profile Data.
/// Replaces Firestore `doctors/{doctorId}` queries and streams.
class SupabaseDoctorRepository {
  SupabaseDoctorRepository._();

  static final SupabaseDoctorRepository instance =
      SupabaseDoctorRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  Future<List<DoctorListing>> fetchVerifiedDoctors() async {
    return fetchAllDoctors(verifiedOnly: true);
  }

  Future<List<DoctorListing>> fetchAllDoctors({
    bool verifiedOnly = true,
  }) async {
    if (!SupabaseBootstrap.isReady) return const [];

    try {
      final query = verifiedOnly
          ? _client.from('doctor_directory').select()
          : _client.from('doctors').select();

      final res = await query.limit(50);
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map((row) => _fromRow(row['doctor_id'] as String? ?? '', row))
          .whereType<DoctorListing>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Real-time stream of doctors.
  /// Converted from Firestore: uses single .eq('verified', true) stream when verifiedOnly is true.
  Stream<List<DoctorListing>> streamAllDoctors({bool verifiedOnly = true}) {
    if (!SupabaseBootstrap.isReady) return const Stream.empty();

    if (verifiedOnly) {
      return _client
          .from('doctors')
          .stream(primaryKey: ['doctor_id'])
          .eq('verified', true)
          .limit(50)
          .map((rows) => rows
              .map((row) => _fromRow(row['doctor_id'] as String? ?? '', row))
              .whereType<DoctorListing>()
              .toList());
    } else {
      return _client
          .from('doctors')
          .stream(primaryKey: ['doctor_id'])
          .limit(50)
          .map((rows) => rows
              .map((row) => _fromRow(row['doctor_id'] as String? ?? '', row))
              .whereType<DoctorListing>()
              .toList());
    }
  }

  /// Real-time stream for a single doctor's profile.
  /// Uses a single `.eq('doctor_id', doctorId)` filter.
  Stream<Map<String, dynamic>?> watchDoctor(String doctorId) {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }

    return _client
        .from('doctors')
        .stream(primaryKey: ['doctor_id'])
        .eq('doctor_id', doctorId)
        .map((rows) {
          if (rows.isEmpty) return null;
          return rows.first;
        });
  }

  Future<bool> isDoctorVerified(
    String doctorId, {
    bool preferCache = true,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) return false;

    try {
      final res = await _client
          .from('doctors')
          .select('verified, deactivated')
          .eq('doctor_id', doctorId)
          .maybeSingle();

      if (res == null) return false;
      final verified = res['verified'] as bool? ?? false;
      final deactivated = res['deactivated'] as bool? ?? false;
      return verified && !deactivated;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchDoctor(String doctorId) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) return null;

    try {
      final res = await _client
          .from('doctors')
          .select()
          .eq('doctor_id', doctorId)
          .maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDoctor(String doctorId, Map<String, dynamic> data) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) return;

    final payload = <String, dynamic>{
      'doctor_id': doctorId,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (data.containsKey('name')) payload['name'] = data['name'];
    if (data.containsKey('email')) payload['email'] = data['email'];
    if (data.containsKey('mobile')) payload['mobile'] = data['mobile'];
    if (data.containsKey('specialization')) {
      payload['specialization'] = data['specialization'];
    }
    if (data.containsKey('qualification')) {
      payload['qualification'] = data['qualification'];
    }
    if (data.containsKey('experienceYears')) {
      payload['experience_years'] = data['experienceYears'];
    }
    if (data.containsKey('consultationFee')) {
      payload['consultation_fee'] = data['consultationFee'];
    }
    if (data.containsKey('clinicName')) {
      payload['clinic_name'] = data['clinicName'];
    }
    if (data.containsKey('city')) payload['city'] = data['city'];
    if (data.containsKey('about')) payload['about'] = data['about'];
    if (data.containsKey('photoUrl')) payload['photo_url'] = data['photoUrl'];
    if (data.containsKey('photoS3Key')) {
      payload['photo_s3_key'] = data['photoS3Key'];
    }
    if (data.containsKey('profileCompleted')) {
      payload['profile_completed'] = data['profileCompleted'];
    }

    await _client.from('doctors').upsert(payload, onConflict: 'doctor_id');
  }

  DoctorListing? _fromRow(String id, Map<String, dynamic> row) {
    final name = (row['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;

    final expRaw = row['experience_years'];
    final exp = expRaw is num
        ? expRaw.toInt()
        : (int.tryParse(expRaw?.toString() ?? '') ?? 1);

    final ratingRaw = row['rating'];
    final rating = ratingRaw is num
        ? ratingRaw.toDouble()
        : (double.tryParse(ratingRaw?.toString() ?? '') ?? 4.5);

    return DoctorListing(
      id: id,
      name: name,
      specialization:
          (row['specialization'] as String?)?.trim() ?? 'General Physician',
      qualification: (row['qualification'] as String?)?.trim() ?? 'MBBS',
      experienceYears: exp,
      rating: rating,
      reviewCount: (row['review_count'] as num?)?.toInt() ?? 0,
      clinicName:
          (row['clinic_name'] as String?)?.trim() ?? '$name Clinic',
      area: (row['area'] as String?)?.trim() ??
          (row['city'] as String?)?.trim() ??
          '',
      distanceKm: 0.0,
      availability: DoctorAvailability.later,
      nextSlot: 'Check availability',
      verified: row['verified'] as bool? ?? false,
      gender: (row['gender'] as String?)?.trim() ?? 'Male',
      languages: const ['English', 'Hindi'],
      city: (row['city'] as String?)?.trim() ?? '',
      addressLine1: (row['address_line1'] as String?)?.trim() ?? '',
      state: (row['state'] as String?)?.trim() ?? '',
      photoUrl: row['photo_url'] as String?,
      photoKey: row['photo_s3_key'] as String?,
    );
  }
}
