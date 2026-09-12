import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_query_limits.dart';
import '../firestore_read_helper.dart';
import '../mappers/referral_firestore_mapper.dart';
import '../models/doctor_referral.dart';
import 'patient_profile_repository.dart';

class ReferralRepository {
  ReferralRepository._();

  static final ReferralRepository instance = ReferralRepository._();

  Future<void> save(DoctorReferral referral) async {
    if (!FirebaseBootstrap.isReady) return;

    await FirebaseFirestore.instance.collection(FirestorePaths.referrals).doc(referral.referralId).set({
      ...ReferralFirestoreMapper.toMap(referral),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (referral.patientId.isNotEmpty &&
        PatientProfileRepository.isRegisteredPatientId(referral.patientId)) {
      final linkOk = await PatientProfileRepository.instance.ensureDoctorPatientLink(
        patientId: referral.patientId,
        doctorId: referral.toDoctorId,
        source: 'referral',
        fromDoctorId: referral.fromDoctorId,
        referralId: referral.referralId,
      );
      if (!linkOk) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message:
              'Referral was saved but the specialist could not be linked to this patient.',
        );
      }
    }
  }

  Future<DoctorReferral?> fetchById(
    String referralId, {
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady || referralId.isEmpty) return null;

    try {
      final snap = await FirestoreReadHelper.getDocument(
        reference: FirebaseFirestore.instance
            .collection(FirestorePaths.referrals)
            .doc(referralId),
        preferCache: preferCache,
      );
      if (!snap.exists) return null;
      return ReferralFirestoreMapper.fromMap(snap.data() ?? {});
    } catch (e, st) {
      if (kDebugMode) debugPrint('fetchById referral $referralId: $e\n$st');
      return null;
    }
  }

  Future<List<DoctorReferral>> fetchSentByDoctor(
    String doctorId, {
    bool preferCache = true,
  }) async {
    return _fetchForDoctorField(
      field: 'fromDoctorId',
      doctorId: doctorId,
      preferCache: preferCache,
    );
  }

  Future<List<DoctorReferral>> fetchReceivedByDoctor(
    String doctorId, {
    bool preferCache = true,
  }) async {
    return _fetchForDoctorField(
      field: 'toDoctorId',
      doctorId: doctorId,
      preferCache: preferCache,
    );
  }

  Future<List<DoctorReferral>> _fetchForDoctorField({
    required String field,
    required String doctorId,
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) return const [];

    final snapshot = await FirestoreReadHelper.getQuery(
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.referrals)
          .where(field, isEqualTo: doctorId)
          .limit(FirestoreQueryLimits.connectionsPage),
      preferCache: preferCache,
    );

    return snapshot.docs
        .map((doc) => ReferralFirestoreMapper.fromMap(doc.data()))
        .whereType<DoctorReferral>()
        .where((r) => r.status == 'sent' || r.status == 'complete' || r.status == 'completed')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
