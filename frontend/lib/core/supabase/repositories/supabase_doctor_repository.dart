import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/patient/models/patient_models.dart';
import '../supabase_bootstrap.dart';
import '../supabase_stream_table.dart';

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
      if (!kReleaseMode && debugTableFetcher != null) {
        final rows = await debugTableFetcher!('doctor_directory');
        return rows
            .map((row) => _fromRow(row['doctor_id'] as String? ?? '', row))
            .whereType<DoctorListing>()
            .toList();
      }

      final res = await _client.from('doctor_directory').select().limit(50);
      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map((row) => _fromRow(row['doctor_id'] as String? ?? '', row))
          .whereType<DoctorListing>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Real-time stream of doctors from safe public view `doctor_directory`.
  /// Subscribes to `doctor_directory_updates` CDC as change signal and refetches
  /// from `doctor_directory` so sensitive base columns are never sent over Realtime.
  Stream<List<DoctorListing>> streamAllDoctors({bool verifiedOnly = true}) {
    if (!SupabaseBootstrap.isReady) return const Stream.empty();

    late final StreamController<List<DoctorListing>> controller;
    RealtimeChannel? channel;

    Future<void> refetch() async {
      try {
        final list = await fetchAllDoctors(verifiedOnly: verifiedOnly);
        if (!controller.isClosed) {
          controller.add(list);
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    }

    Timer? pollTimer;
    controller = StreamController<List<DoctorListing>>.broadcast(
      onListen: () async {
        // Initial fetch from safe doctor_directory view
        await refetch();

        if (SupabaseBootstrap.isProduction) {
          // In production: do not open Realtime channel; use periodic polling
          pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
            if (!controller.isClosed) {
              await refetch();
            }
          });
        } else {
          // Listen for change signal on doctor_directory_updates in staging
          channel = _client.channel('public:doctor_directory_updates')
            ..onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'doctor_directory_updates',
              callback: (_) async {
                await refetch();
              },
            )
            ..subscribe();
        }
      },
      onCancel: () async {
        pollTimer?.cancel();
        if (channel != null) {
          await _client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  /// Real-time stream for a single doctor's public directory profile.
  /// Refetches from safe `doctor_directory` view on change signal.
  Stream<Map<String, dynamic>?> watchDoctor(String doctorId) {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }

    late final StreamController<Map<String, dynamic>?> controller;
    RealtimeChannel? channel;
    Timer? pollTimer;

    Future<void> refetch() async {
      try {
        if (!kReleaseMode && debugTableFetcher != null) {
          final rows = await debugTableFetcher!('doctor_directory');
          final match = rows.firstWhere(
            (r) => r['doctor_id'] == doctorId,
            orElse: () => rows.isNotEmpty ? rows.first : <String, dynamic>{},
          );
          if (!controller.isClosed) {
            controller.add(match.isEmpty ? null : match);
          }
          return;
        }

        final res = await _client
            .from('doctor_directory')
            .select()
            .eq('doctor_id', doctorId)
            .maybeSingle();
        if (!controller.isClosed) {
          controller.add(res);
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    }

    controller = StreamController<Map<String, dynamic>?>.broadcast(
      onListen: () async {
        await refetch();

        if (SupabaseBootstrap.isProduction) {
          // In production: do not open Realtime channel; use periodic polling
          pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
            if (!controller.isClosed) {
              await refetch();
            }
          });
        } else {
          channel = _client.channel('public:doctor_directory_updates:$doctorId')
            ..onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'doctor_directory_updates',
              callback: (_) async {
                await refetch();
              },
            )
            ..subscribe();
        }
      },
      onCancel: () async {
        pollTimer?.cancel();
        if (channel != null) {
          await _client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
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
