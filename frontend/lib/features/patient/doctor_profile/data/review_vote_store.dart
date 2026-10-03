import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/session/patient_session.dart';

/// Local cache of which reviews the current patient has liked (offline fallback).
abstract final class ReviewVoteStore {
  ReviewVoteStore._();

  static String _key(String reviewId) {
    final patientId = PatientSession.loggedInPatientId;
    return 'review_like_${patientId}_$reviewId';
  }

  static Future<Set<String>> likedReviewIds(Iterable<String> reviewIds) async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return const {};

    final prefs = await SharedPreferences.getInstance();
    final liked = <String>{};
    for (final reviewId in reviewIds) {
      if (prefs.getBool(_key(reviewId)) == true) {
        liked.add(reviewId);
      }
    }
    return liked;
  }

  static Future<void> setLiked(String reviewId, bool liked) async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    if (liked) {
      await prefs.setBool(_key(reviewId), true);
    } else {
      await prefs.remove(_key(reviewId));
    }
  }
}
