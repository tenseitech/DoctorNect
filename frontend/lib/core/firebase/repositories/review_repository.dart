import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../features/patient/data/registered_doctors_store.dart';
import '../../../features/patient/doctor_profile/models/doctor_profile_detail.dart';
import '../../supabase/repositories/supabase_review_repository.dart';

class ReviewRepository {
  ReviewRepository._();

  static final ReviewRepository instance = ReviewRepository._();

  /// Fetches an existing review submitted by [patientId] for [doctorId].
  Future<PatientDoctorReview?> fetchReviewForPatientAndDoctor({
    required String patientId,
    required String doctorId,
  }) async {
    return SupabaseReviewRepository.instance.fetchReviewForPatientAndDoctor(
        patientId: patientId,
        doctorId: doctorId,
      );
  }

  /// Recalculates local cache only — doctor rating aggregates are updated by
  /// Cloud Functions (Admin SDK). Clients must not write doctors.rating.
  Future<void> recalculateDoctorRating(String doctorId) async {
    return SupabaseReviewRepository.instance
          .recalculateDoctorRating(doctorId);
  }

  /// Submits or updates a rating/review for a given doctor. Each patient can rate a given doctor only once.
  Future<String?> submitReview({
    required String patientId,
    required String doctorId,
    required String appointmentId,
    required int rating,
    required String comment,
    required String patientName,
  }) async {
    return SupabaseReviewRepository.instance.submitReview(
        patientId: patientId,
        doctorId: doctorId,
        appointmentId: appointmentId,
        rating: rating,
        comment: comment,
        patientName: patientName,
      );
  }

  Future<bool> updateReview({
    required String reviewId,
    required String patientId,
    required int rating,
    required String comment,
  }) async {
    return SupabaseReviewRepository.instance.updateReview(
        reviewId: reviewId,
        patientId: patientId,
        rating: rating,
        comment: comment,
      );
  }

  Future<String?> findReviewIdForAppointment({
    required String appointmentId,
    required String patientId,
  }) async {
    return SupabaseReviewRepository.instance.findReviewIdForAppointment(
        appointmentId: appointmentId,
        patientId: patientId,
      );
  }

  Future<PatientDoctorReview?> fetchReview(String reviewId) async {
    return SupabaseReviewRepository.instance.fetchReview(reviewId);
  }

  Future<List<PatientDoctorReview>> fetchForDoctor(
    String doctorId, {
    int limit = 50,
  }) async {
    return SupabaseReviewRepository.instance
          .fetchForDoctor(doctorId, limit: limit);
  }

  /// Returns `true` when liked, `false` when unliked, `null` on failure.
  Future<bool?> toggleHelpfulVote({
    required String reviewId,
    required String patientId,
  }) async {
    return SupabaseReviewRepository.instance.toggleHelpfulVote(
        reviewId: reviewId,
        patientId: patientId,
      );
  }

  Future<Set<String>> likedReviewIdsForPatient({
    required String patientId,
    required List<String> reviewIds,
  }) async {
    return SupabaseReviewRepository.instance.likedReviewIdsForPatient(
        patientId: patientId,
        reviewIds: reviewIds,
      );
  }
}
