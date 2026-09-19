import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'profile_completion_checker.dart';
import '../enums/user_type.dart';
import '../firebase/firebase_bootstrap.dart';
import '../firebase/firestore_paths.dart';
import '../firebase/firestore_read_helper.dart';

/// Tracks whether a non-patient user has completed their full profile.
class ProfileCompletionService extends ChangeNotifier {
  ProfileCompletionService._();

  static final ProfileCompletionService instance = ProfileCompletionService._();

  bool _isComplete = true;

  /// `true` for patients and legacy accounts missing the field.
  bool get isComplete => _isComplete;

  Future<void> refreshForUser({
    required UserType role,
    required String uid,
    String? profileId,
  }) async {
    if (role.isPatient) {
      _isComplete = true;
      notifyListeners();
      return;
    }

    if (!FirebaseBootstrap.isReady || uid.isEmpty) {
      return;
    }

    try {
      final userSnap = await FirestoreReadHelper.getDocument(
        reference: FirebaseFirestore.instance
            .collection(FirestorePaths.users)
            .doc(uid),
        preferCache: false,
      );
      final userData = userSnap.data();
      if (userData != null) {
        final flag = userData['profileCompleted'];
        if (flag is bool) {
          _isComplete = flag;
          notifyListeners();
          return;
        }
      }

      if (role.isAmbulance && profileId != null && profileId.isNotEmpty) {
        await _refreshFromAmbulanceDoc(profileId);
        return;
      }

      _isComplete = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('ProfileCompletionService.refresh failed: $e');
    }
  }

  Future<void> refreshForAmbulance(String ambulanceId) async {
    if (ambulanceId.isEmpty) return;
    await _refreshFromAmbulanceDoc(ambulanceId);
  }

  Future<void> _refreshFromAmbulanceDoc(String ambulanceId) async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      final snap = await FirestoreReadHelper.getDocument(
        reference: FirebaseFirestore.instance
            .collection(FirestorePaths.ambulances)
            .doc(ambulanceId),
        preferCache: false,
      );
      final flag = snap.data()?['profileCompleted'];
      _isComplete = flag is bool ? flag : true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode)
        debugPrint('ProfileCompletionService ambulance refresh: $e');
    }
  }

  Future<void> markComplete({
    required UserType role,
    required String uid,
    required String profileId,
  }) async {
    if (!FirebaseBootstrap.isReady) return;

    final batch = FirebaseFirestore.instance.batch();
    final userRef =
        FirebaseFirestore.instance.collection(FirestorePaths.users).doc(uid);
    batch.set(
      userRef,
      {
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    final roleCollection = switch (role) {
      UserType.doctor => FirestorePaths.doctors,
      UserType.medicalStore => FirestorePaths.medicalStores,
      UserType.lab => FirestorePaths.labs,
      UserType.ambulance => FirestorePaths.ambulances,
      _ => null,
    };

    if (roleCollection != null && profileId.isNotEmpty) {
      batch.set(
        FirebaseFirestore.instance.collection(roleCollection).doc(profileId),
        {
          'profileCompleted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
    _isComplete = true;
    notifyListeners();
  }

  Future<void> markAmbulanceComplete(String ambulanceId) async {
    if (!FirebaseBootstrap.isReady || ambulanceId.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.ambulances)
        .doc(ambulanceId)
        .set(
      {
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    _isComplete = true;
    notifyListeners();
  }

  void reset() {
    _isComplete = true;
    notifyListeners();
  }

  Future<void> evaluateAndMarkFromRoleDoc({
    required UserType role,
    required String uid,
    required String profileId,
  }) async {
    if (_isComplete || !FirebaseBootstrap.isReady || profileId.isEmpty) return;

    final collection = switch (role) {
      UserType.doctor => FirestorePaths.doctors,
      UserType.medicalStore => FirestorePaths.medicalStores,
      UserType.lab => FirestorePaths.labs,
      UserType.ambulance => FirestorePaths.ambulances,
      _ => null,
    };
    if (collection == null) return;

    try {
      final snap = await FirestoreReadHelper.getDocument(
        reference:
            FirebaseFirestore.instance.collection(collection).doc(profileId),
        preferCache: false,
      );
      final data = snap.data();
      final complete = switch (role) {
        UserType.doctor => ProfileCompletionChecker.isDoctorDocComplete(data),
        UserType.medicalStore =>
          ProfileCompletionChecker.isPharmacyDocComplete(data),
        UserType.lab => ProfileCompletionChecker.isLabDocComplete(data),
        UserType.ambulance =>
          ProfileCompletionChecker.isAmbulanceDocComplete(data),
        _ => false,
      };
      if (!complete) return;

      if (role.isAmbulance) {
        await markAmbulanceComplete(profileId);
        return;
      }
      if (uid.isNotEmpty) {
        await markComplete(role: role, uid: uid, profileId: profileId);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ProfileCompletionService.evaluate: $e');
    }
  }
}
