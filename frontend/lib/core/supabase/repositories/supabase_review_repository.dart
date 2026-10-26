import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/patient/data/registered_doctors_store.dart';
import '../../../features/patient/doctor_profile/models/doctor_profile_detail.dart';
import '../supabase_bootstrap.dart';

/// Supabase Repository for Doctor Reviews and Ratings.
/// Replaces Firestore `reviews/{reviewId}` and `review_public/{reviewId}`.
class SupabaseReviewRepository {
  SupabaseReviewRepository._();

  static final SupabaseReviewRepository instance = SupabaseReviewRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  Future<PatientDoctorReview?> fetchReviewForPatientAndDoctor({
    required String patientId,
    required String doctorId,
  }) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty || doctorId.isEmpty) {
      return null;
    }

    try {
      final res = await _client
          .from('reviews')
          .select()
          .eq('patient_id', patientId)
          .eq('doctor_id', doctorId)
          .maybeSingle();

      if (res == null) return null;
      return _reviewFromRow(res);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[SupabaseReviewRepository] fetchReviewForPatientAndDoctor error: $e\n$st');
      }
      return null;
    }
  }

  Future<void> recalculateDoctorRating(String doctorId) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) return;

    try {
      final res = await _client
          .from('review_public')
          .select('rating')
          .eq('doctor_id', doctorId);

      final rows = List<Map<String, dynamic>>.from(res as List);
      final count = rows.length;
      double avgRating = 0.0;
      if (count > 0) {
        double total = 0.0;
        for (final row in rows) {
          total += (row['rating'] as num?)?.toDouble() ?? 0.0;
        }
        avgRating = double.parse((total / count).toStringAsFixed(1));
      }

      RegisteredDoctorsStore.instance.updateDoctorRating(
        doctorId: doctorId,
        rating: avgRating,
        reviewCount: count,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[SupabaseReviewRepository] recalculateDoctorRating error: $e\n$st');
      }
    }
  }

  Future<String?> submitReview({
    required String patientId,
    required String doctorId,
    required String appointmentId,
    required int rating,
    required String comment,
    required String patientName,
  }) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty || doctorId.isEmpty) {
      return null;
    }
    if (rating < 1 || rating > 5) return null;

    final reviewId = '${patientId}_$doctorId';
    final existingReview = await fetchReviewForPatientAndDoctor(
      patientId: patientId,
      doctorId: doctorId,
    );

    final reviewRow = <String, dynamic>{
      'review_id': reviewId,
      'patient_id': patientId,
      'doctor_id': doctorId,
      if (appointmentId.isNotEmpty) 'appointment_id': appointmentId,
      'patient_name': patientName.isNotEmpty ? patientName : 'Patient',
      'rating': rating,
      'comment': comment.isNotEmpty ? comment : 'No written comment.',
      'helpful_count': existingReview?.helpfulCount ?? 0,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (existingReview == null) {
      reviewRow['created_at'] = DateTime.now().toIso8601String();
    }

    try {
      // 1. Upsert private review record
      await _client.from('reviews').upsert(reviewRow, onConflict: 'review_id');

      // 2. Upsert public anonymized review projection
      final publicRow = <String, dynamic>{
        'review_id': reviewId,
        'doctor_id': doctorId,
        'rating': rating,
        'comment': comment.isNotEmpty ? comment : 'No written comment.',
        'masked_name': _maskName(patientName),
        'helpful_count': existingReview?.helpfulCount ?? 0,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (existingReview == null) {
        publicRow['created_at'] = DateTime.now().toIso8601String();
      }
      await _client
          .from('review_public')
          .upsert(publicRow, onConflict: 'review_id');

      unawaited(recalculateDoctorRating(doctorId));
      return reviewId;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SupabaseReviewRepository] submitReview error: $e\n$st');
      }
      return null;
    }
  }

  Future<bool> updateReview({
    required String reviewId,
    required String patientId,
    required int rating,
    required String comment,
  }) async {
    if (!SupabaseBootstrap.isReady || reviewId.isEmpty || patientId.isEmpty) {
      return false;
    }
    if (rating < 1 || rating > 5) return false;

    try {
      final res = await _client
          .from('reviews')
          .select('doctor_id, patient_id')
          .eq('review_id', reviewId)
          .maybeSingle();

      if (res == null || res['patient_id'] != patientId) return false;
      final doctorId = res['doctor_id'] as String? ?? '';

      await _client.from('reviews').update({
        'rating': rating,
        'comment': comment.isNotEmpty ? comment : 'No written comment.',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('review_id', reviewId);

      await _client.from('review_public').update({
        'rating': rating,
        'comment': comment.isNotEmpty ? comment : 'No written comment.',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('review_id', reviewId);

      if (doctorId.isNotEmpty) {
        unawaited(recalculateDoctorRating(doctorId));
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SupabaseReviewRepository] updateReview error: $e\n$st');
      }
      return false;
    }
  }

  Future<String?> findReviewIdForAppointment({
    required String appointmentId,
    required String patientId,
  }) async {
    if (!SupabaseBootstrap.isReady ||
        appointmentId.isEmpty ||
        patientId.isEmpty) {
      return null;
    }

    try {
      final res = await _client
          .from('reviews')
          .select('review_id')
          .eq('appointment_id', appointmentId)
          .eq('patient_id', patientId)
          .maybeSingle();

      return res?['review_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<PatientDoctorReview?> fetchReview(String reviewId) async {
    if (!SupabaseBootstrap.isReady || reviewId.isEmpty) return null;

    try {
      final res = await _client
          .from('reviews')
          .select()
          .eq('review_id', reviewId)
          .maybeSingle();

      if (res == null) return null;
      return _reviewFromRow(res);
    } catch (_) {
      return null;
    }
  }

  Future<List<PatientDoctorReview>> fetchForDoctor(
    String doctorId, {
    int limit = 50,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) return const [];

    try {
      final res = await _client
          .from('review_public')
          .select()
          .eq('doctor_id', doctorId)
          .order('created_at', ascending: false)
          .limit(limit);

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows.map(_reviewFromPublicRow).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Realtime stream for public doctor reviews.
  /// Streams base table changes (`reviews`) and applies refetch strategy from safe public records.
  Stream<List<PatientDoctorReview>> watchForDoctor(String doctorId) {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }

    late final StreamController<List<PatientDoctorReview>> controller;
    RealtimeChannel? channel;
    Timer? pollTimer;

    controller = StreamController<List<PatientDoctorReview>>.broadcast(
      onListen: () async {
        // 1. Initial load
        final initial = await fetchForDoctor(doctorId);
        if (!controller.isClosed) {
          controller.add(initial);
        }

        if (SupabaseBootstrap.isProduction) {
          // In production: do not open Realtime channel; use periodic polling
          pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
            if (!controller.isClosed) {
              final updated = await fetchForDoctor(doctorId);
              if (!controller.isClosed) {
                controller.add(updated);
              }
            }
          });
        } else {
          // 2. Base table realtime subscription + refetch strategy in staging
          channel = _client.channel('public:reviews:doctor:$doctorId')
            ..onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'reviews',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'doctor_id',
                value: doctorId,
              ),
              callback: (_) async {
                final updated = await fetchForDoctor(doctorId);
                if (!controller.isClosed) {
                  controller.add(updated);
                }
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

  Future<bool?> toggleHelpfulVote({
    required String reviewId,
    required String patientId,
  }) async {
    if (!SupabaseBootstrap.isReady || reviewId.isEmpty || patientId.isEmpty) {
      return null;
    }

    try {
      // Check existing vote
      final existing = await _client
          .from('review_votes')
          .select('patient_id')
          .eq('review_id', reviewId)
          .eq('patient_id', patientId)
          .maybeSingle();

      if (existing != null) {
        // Delete vote
        await _client
            .from('review_votes')
            .delete()
            .eq('review_id', reviewId)
            .eq('patient_id', patientId);

        // Decrement helpful count
        await _client.rpc('decrement_review_helpful_count', params: {
          'p_review_id': reviewId,
        }).catchError((_) async {
          // Fallback direct update
          final current = await _client
              .from('review_public')
              .select('helpful_count')
              .eq('review_id', reviewId)
              .maybeSingle();
          final count = (current?['helpful_count'] as num?)?.toInt() ?? 1;
          await _client
              .from('review_public')
              .update({'helpful_count': (count - 1).clamp(0, 999999)}).eq(
                  'review_id', reviewId);
          await _client
              .from('reviews')
              .update({'helpful_count': (count - 1).clamp(0, 999999)}).eq(
                  'review_id', reviewId);
        });
        return false;
      } else {
        // Insert vote
        await _client.from('review_votes').insert({
          'review_id': reviewId,
          'patient_id': patientId,
          'created_at': DateTime.now().toIso8601String(),
        });

        // Increment helpful count
        await _client.rpc('increment_review_helpful_count', params: {
          'p_review_id': reviewId,
        }).catchError((_) async {
          final current = await _client
              .from('review_public')
              .select('helpful_count')
              .eq('review_id', reviewId)
              .maybeSingle();
          final count = (current?['helpful_count'] as num?)?.toInt() ?? 0;
          await _client
              .from('review_public')
              .update({'helpful_count': count + 1}).eq('review_id', reviewId);
          await _client
              .from('reviews')
              .update({'helpful_count': count + 1}).eq('review_id', reviewId);
        });
        return true;
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[SupabaseReviewRepository] toggleHelpfulVote error: $e\n$st');
      }
      return null;
    }
  }

  Future<Set<String>> likedReviewIdsForPatient({
    required String patientId,
    required List<String> reviewIds,
  }) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty || reviewIds.isEmpty) {
      return const {};
    }

    try {
      final res = await _client
          .from('review_votes')
          .select('review_id')
          .eq('patient_id', patientId)
          .filter('review_id', 'in', reviewIds);

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows.map((r) => r['review_id'] as String).toSet();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[SupabaseReviewRepository] likedReviewIdsForPatient error: $e\n$st');
      }
      return const {};
    }
  }

  PatientDoctorReview _reviewFromRow(Map<String, dynamic> data) {
    final name = data['patient_name'] as String? ?? 'Patient';
    DateTime date = DateTime.now();
    if (data['created_at'] != null) {
      date = DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now();
    }
    return PatientDoctorReview(
      id: data['review_id'] as String? ?? '',
      maskedName: _maskName(name),
      rating: (data['rating'] as num?)?.toInt() ?? 5,
      text: data['comment'] as String? ?? 'No written comment.',
      date: date,
      patientId: data['patient_id'] as String?,
      doctorReply: data['doctor_reply'] as String?,
      helpfulCount: (data['helpful_count'] as num?)?.toInt() ?? 0,
    );
  }

  PatientDoctorReview _reviewFromPublicRow(Map<String, dynamic> data) {
    DateTime date = DateTime.now();
    if (data['created_at'] != null) {
      date = DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now();
    }
    return PatientDoctorReview(
      id: data['review_id'] as String? ?? '',
      maskedName: data['masked_name'] as String? ?? 'Patient',
      rating: (data['rating'] as num?)?.toInt() ?? 5,
      text: data['comment'] as String? ?? 'No written comment.',
      date: date,
      doctorReply: data['doctor_reply'] as String?,
      helpfulCount: (data['helpful_count'] as num?)?.toInt() ?? 0,
    );
  }

  String _maskName(String patientName) {
    final parts = patientName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'Patient';
    if (parts.length == 1) return '${parts.first[0]}.';
    return '${parts.first[0]}. ${parts.last[0]}.';
  }
}
