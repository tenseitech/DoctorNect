import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../features/patient/data/registered_doctors_store.dart';
import '../../../features/patient/doctor_profile/models/doctor_profile_detail.dart';
import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_read_helper.dart';

class ReviewRepository {
  ReviewRepository._();

  static final ReviewRepository instance = ReviewRepository._();

  /// Fetches an existing review submitted by [patientId] for [doctorId].
  Future<PatientDoctorReview?> fetchReviewForPatientAndDoctor({
    required String patientId,
    required String doctorId,
  }) async {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty || doctorId.isEmpty) {
      return null;
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection(FirestorePaths.reviews)
          .doc('${patientId}_$doctorId');
      final snap = await FirestoreReadHelper.getDocument(
        reference: docRef,
        preferCache: false,
      );
      if (snap.exists && snap.data() != null) {
        return reviewFromSnapshot(snap);
      }

      final query = FirebaseFirestore.instance
          .collection(FirestorePaths.reviews)
          .where('patientId', isEqualTo: patientId)
          .where('doctorId', isEqualTo: doctorId)
          .limit(1);
      final snapshot = await FirestoreReadHelper.getQuery(
        query: query,
        preferCache: false,
      );
      if (snapshot.docs.isNotEmpty) {
        return _reviewFromDoc(snapshot.docs.first.id, snapshot.docs.first.data());
      }
      return null;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[ReviewRepository] fetchReviewForPatientAndDoctor error: $e\n$st');
      }
      return null;
    }
  }

  /// Recalculates local cache only — doctor rating aggregates are updated by
  /// Cloud Functions (Admin SDK). Clients must not write doctors.rating.
  Future<void> recalculateDoctorRating(String doctorId) async {
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(FirestorePaths.reviews)
          .where('doctorId', isEqualTo: doctorId)
          .get(const GetOptions(source: Source.server));

      final docs = snapshot.docs;
      final count = docs.length;
      double avgRating = 0.0;
      if (count > 0) {
        double total = 0.0;
        for (final doc in docs) {
          total += (doc.data()['rating'] as num?)?.toDouble() ?? 0.0;
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
        debugPrint('[ReviewRepository] recalculateDoctorRating failed: $e\n$st');
      }
    }
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
    if (!FirebaseBootstrap.isReady || patientId.isEmpty || doctorId.isEmpty) {
      return null;
    }
    if (rating < 1 || rating > 5) return null;

    final existingReview = await fetchReviewForPatientAndDoctor(
      patientId: patientId,
      doctorId: doctorId,
    );

    final firestore = FirebaseFirestore.instance;
    final reviewId = existingReview?.id ?? '${patientId}_$doctorId';
    final reviewRef = firestore.collection(FirestorePaths.reviews).doc(reviewId);

    final reviewData = <String, dynamic>{
      'patientId': patientId,
      'doctorId': doctorId,
      if (appointmentId.isNotEmpty) 'appointmentId': appointmentId,
      'rating': rating,
      'comment': comment.isNotEmpty ? comment : 'No written comment.',
      if (patientName.isNotEmpty) 'patientName': patientName,
      'helpfulCount': existingReview?.helpfulCount ?? 0,
      'createdAt': existingReview?.date != null ? Timestamp.fromDate(existingReview!.date) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await reviewRef.set(reviewData, SetOptions(merge: true));
      unawaited(recalculateDoctorRating(doctorId));
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('[ReviewRepository] submit failed (${e.code}): ${e.message}');
      }
      return null;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[ReviewRepository] submit failed: $e\n$st');
      return null;
    }

    return reviewId;
  }

  Future<bool> updateReview({
    required String reviewId,
    required String patientId,
    required int rating,
    required String comment,
  }) async {
    if (!FirebaseBootstrap.isReady || reviewId.isEmpty || patientId.isEmpty) {
      return false;
    }
    if (rating < 1 || rating > 5) return false;

    final firestore = FirebaseFirestore.instance;
    final reviewRef = firestore.collection(FirestorePaths.reviews).doc(reviewId);

    try {
      final reviewSnap = await reviewRef.get();
      if (!reviewSnap.exists) return false;

      final data = reviewSnap.data()!;
      final reviewPatientId = data['patientId'] as String?;
      if (reviewPatientId != patientId) return false;

      final doctorId = data['doctorId'] as String? ?? '';

      await reviewRef.update({
        'rating': rating,
        'comment': comment.isNotEmpty ? comment : 'No written comment.',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (doctorId.isNotEmpty) {
        unawaited(recalculateDoctorRating(doctorId));
      }

      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[ReviewRepository] updateReview failed: $e\n$st');
      return false;
    }
  }

  Future<String?> findReviewIdForAppointment({
    required String appointmentId,
    required String patientId,
  }) async {
    if (!FirebaseBootstrap.isReady || appointmentId.isEmpty || patientId.isEmpty) {
      return null;
    }

    try {
      final query = FirebaseFirestore.instance
          .collection(FirestorePaths.reviews)
          .where('appointmentId', isEqualTo: appointmentId)
          .where('patientId', isEqualTo: patientId)
          .limit(1);
      final snapshot = await FirestoreReadHelper.getQuery(
        query: query,
        preferCache: true,
      );
      if (snapshot.docs.isEmpty) return null;
      return snapshot.docs.first.id;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[ReviewRepository] findReviewIdForAppointment failed: $e\n$st');
      return null;
    }
  }

  Future<PatientDoctorReview?> fetchReview(String reviewId) async {
    if (!FirebaseBootstrap.isReady || reviewId.isEmpty) return null;
    try {
      final docRef = FirebaseFirestore.instance
          .collection(FirestorePaths.reviews)
          .doc(reviewId);
      final snap = await FirestoreReadHelper.getDocument(
        reference: docRef,
        preferCache: true,
      );
      return reviewFromSnapshot(snap);
    } catch (_) {
      return null;
    }
  }

  Future<List<PatientDoctorReview>> fetchForDoctor(String doctorId, {int limit = 50}) async {
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) return const [];

    try {
      final snapshot = await FirestoreReadHelper.getQuery(
        query: FirebaseFirestore.instance
            .collection(FirestorePaths.reviews)
            .where('doctorId', isEqualTo: doctorId)
            .limit(limit),
        preferCache: true,
      );

      final reviews = snapshot.docs.map((doc) => _reviewFromDoc(doc.id, doc.data())).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return reviews;
    } catch (_) {
      return const [];
    }
  }

  PatientDoctorReview? reviewFromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return _reviewFromDoc(doc.id, data);
  }

  PatientDoctorReview _reviewFromDoc(String id, Map<String, dynamic> data) {
    final name = data['patientName'] as String? ?? 'Patient';
    return PatientDoctorReview(
      id: id,
      maskedName: _maskName(name),
      rating: (data['rating'] as num?)?.toInt() ?? 5,
      text: data['comment'] as String? ?? 'No written comment.',
      date: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      patientId: data['patientId'] as String?,
      doctorReply: data['doctorReply'] as String?,
      helpfulCount: (data['helpfulCount'] as num?)?.toInt() ?? 0,
    );
  }

  String _maskName(String patientName) {
    final parts = patientName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'Patient';
    if (parts.length == 1) return '${parts.first[0]}.';
    return '${parts.first[0]}. ${parts.last[0]}.';
  }

  /// Returns `true` when liked, `false` when unliked, `null` on failure.
  Future<bool?> toggleHelpfulVote({
    required String reviewId,
    required String patientId,
  }) async {
    if (!FirebaseBootstrap.isReady || reviewId.isEmpty || patientId.isEmpty) {
      return null;
    }

    final firestore = FirebaseFirestore.instance;
    final reviewRef = firestore.collection(FirestorePaths.reviews).doc(reviewId);
    final voteRef = reviewRef.collection('votes').doc(patientId);

    try {
      return await firestore.runTransaction<bool>((tx) async {
        final reviewSnap = await tx.get(reviewRef);
        if (!reviewSnap.exists) return false;

        final voteSnap = await tx.get(voteRef);

        if (voteSnap.exists) {
          tx.delete(voteRef);
          return false;
        }

        tx.set(voteRef, {
          'patientId': patientId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
    } catch (e, st) {
      if (kDebugMode) debugPrint('[ReviewRepository] toggleHelpfulVote failed: $e\n$st');
      return null;
    }
  }

  Future<Set<String>> likedReviewIdsForPatient({
    required String patientId,
    required List<String> reviewIds,
  }) async {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty || reviewIds.isEmpty) {
      return const {};
    }

    final firestore = FirebaseFirestore.instance;
    final liked = <String>{};

    try {
      await Future.wait(reviewIds.map((reviewId) async {
        final snap = await firestore
            .collection(FirestorePaths.reviews)
            .doc(reviewId)
            .collection('votes')
            .doc(patientId)
            .get();
        if (snap.exists) liked.add(reviewId);
      }));
    } catch (e, st) {
      if (kDebugMode) debugPrint('[ReviewRepository] likedReviewIdsForPatient failed: $e\n$st');
    }

    return liked;
  }
}
