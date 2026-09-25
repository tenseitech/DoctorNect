import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../auth/verification_lifecycle.dart';
import '../enums/user_type.dart';
import '../firebase/firestore_paths.dart';

/// Data model representing a professional applicant for Super Admin review.
class VerificationApplicant {
  const VerificationApplicant({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.mobile,
    required this.role,
    required this.profileId,
    required this.verificationStatus,
    required this.verified,
    this.rejectionReason,
    this.submittedAt,
    this.createdAt,
    this.roleData = const {},
  });

  final String uid;
  final String displayName;
  final String email;
  final String mobile;
  final UserType role;
  final String profileId;
  final VerificationStage verificationStatus;
  final bool verified;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final DateTime? createdAt;
  final Map<String, dynamic> roleData;

  factory VerificationApplicant.fromMap(
    String uid,
    Map<String, dynamic> data, {
    Map<String, dynamic> roleData = const {},
  }) {
    final roleStr = data['role'] as String? ?? 'patient';
    final role = switch (roleStr.toLowerCase()) {
      'doctor' => UserType.doctor,
      'medicalstore' || 'pharmacy' => UserType.medicalStore,
      'lab' => UserType.lab,
      'ambulance' => UserType.ambulance,
      'super_admin' || 'superadmin' => UserType.superAdmin,
      _ => UserType.patient,
    };

    final verified = data['verified'] == true;
    final statusStr = data['verificationStatus'] as String? ??
        data['status'] as String? ??
        (verified ? 'verified' : 'registered');

    final submittedTs = data['submittedAt'] as Timestamp?;
    final createdTs = data['createdAt'] as Timestamp?;

    return VerificationApplicant(
      uid: uid,
      displayName: data['displayName'] as String? ?? 'New Professional',
      email: data['email'] as String? ?? '',
      mobile: data['mobile'] as String? ?? '',
      role: role,
      profileId: data['profileId'] as String? ?? '',
      verificationStatus: verified
          ? VerificationStage.verified
          : VerificationStage.fromString(statusStr),
      verified: verified,
      rejectionReason: data['rejectionReason'] as String?,
      submittedAt: submittedTs?.toDate(),
      createdAt: createdTs?.toDate(),
      roleData: roleData,
    );
  }
}

/// Service handling Super Admin verification workflows.
class SuperAdminVerificationService {
  SuperAdminVerificationService._();

  static final SuperAdminVerificationService instance =
      SuperAdminVerificationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream list of non-patient accounts for verification.
  Stream<List<VerificationApplicant>> streamApplicants({
    UserType? roleFilter,
    VerificationStage? stageFilter,
  }) {
    return _firestore
        .collection(FirestorePaths.users)
        .snapshots()
        .map((snapshot) {
      final list = <VerificationApplicant>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final roleStr = data['role'] as String? ?? '';
        if (roleStr.toLowerCase() == 'patient') continue;

        final applicant = VerificationApplicant.fromMap(doc.id, data);
        if (roleFilter != null && applicant.role != roleFilter) {
          continue;
        }
        if (stageFilter != null &&
            applicant.verificationStatus != stageFilter) {
          continue;
        }
        list.add(applicant);
      }

      list.sort((a, b) {
        final aTime = a.submittedAt ?? a.createdAt ?? DateTime(2000);
        final bTime = b.submittedAt ?? b.createdAt ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      return list;
    });
  }

  /// Fetches role-specific doc data (e.g., license, council numbers) for review modal.
  Future<Map<String, dynamic>> fetchRoleDetails(
    UserType role,
    String profileId,
  ) async {
    if (profileId.isEmpty) return {};
    final collection = switch (role) {
      UserType.doctor => FirestorePaths.doctors,
      UserType.medicalStore => FirestorePaths.medicalStores,
      UserType.lab => FirestorePaths.labs,
      UserType.ambulance => FirestorePaths.ambulances,
      _ => null,
    };
    if (collection == null) return {};

    try {
      final snap = await _firestore.collection(collection).doc(profileId).get();
      return snap.data() ?? {};
    } catch (e) {
      if (kDebugMode) debugPrint('fetchRoleDetails error: $e');
      return {};
    }
  }

  /// Approve applicant and unlock operational features.
  Future<bool> approveProfile({
    required String uid,
    required UserType role,
    required String profileId,
  }) async {
    try {
      final batch = _firestore.batch();
      final userRef = _firestore.collection(FirestorePaths.users).doc(uid);

      batch.set(
        userRef,
        {
          'verified': true,
          'verificationStatus': 'verified',
          'status': 'approved',
          'rejectionReason': FieldValue.delete(),
          'verifiedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final roleCol = switch (role) {
        UserType.doctor => FirestorePaths.doctors,
        UserType.medicalStore => FirestorePaths.medicalStores,
        UserType.lab => FirestorePaths.labs,
        UserType.ambulance => FirestorePaths.ambulances,
        _ => null,
      };

      if (roleCol != null && profileId.isNotEmpty) {
        final roleRef = _firestore.collection(roleCol).doc(profileId);
        batch.set(
          roleRef,
          {
            'verified': true,
            'verificationStatus': 'verified',
            'status': 'approved',
            'rejectionReason': FieldValue.delete(),
            'verifiedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('approveProfile error: $e');
      return false;
    }
  }

  /// Request corrections/revisions with a reason.
  Future<bool> requestRevision({
    required String uid,
    required UserType role,
    required String profileId,
    required String reason,
  }) async {
    try {
      final batch = _firestore.batch();
      final userRef = _firestore.collection(FirestorePaths.users).doc(uid);

      batch.set(
        userRef,
        {
          'verified': false,
          'verificationStatus': 'revision_requested',
          'status': 'revision_requested',
          'rejectionReason': reason.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final roleCol = switch (role) {
        UserType.doctor => FirestorePaths.doctors,
        UserType.medicalStore => FirestorePaths.medicalStores,
        UserType.lab => FirestorePaths.labs,
        UserType.ambulance => FirestorePaths.ambulances,
        _ => null,
      };

      if (roleCol != null && profileId.isNotEmpty) {
        final roleRef = _firestore.collection(roleCol).doc(profileId);
        batch.set(
          roleRef,
          {
            'verified': false,
            'verificationStatus': 'revision_requested',
            'status': 'revision_requested',
            'rejectionReason': reason.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('requestRevision error: $e');
      return false;
    }
  }

  /// Reject application with reason.
  Future<bool> rejectProfile({
    required String uid,
    required UserType role,
    required String profileId,
    required String reason,
  }) async {
    try {
      final batch = _firestore.batch();
      final userRef = _firestore.collection(FirestorePaths.users).doc(uid);

      batch.set(
        userRef,
        {
          'verified': false,
          'verificationStatus': 'rejected',
          'status': 'rejected',
          'rejectionReason': reason.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final roleCol = switch (role) {
        UserType.doctor => FirestorePaths.doctors,
        UserType.medicalStore => FirestorePaths.medicalStores,
        UserType.lab => FirestorePaths.labs,
        UserType.ambulance => FirestorePaths.ambulances,
        _ => null,
      };

      if (roleCol != null && profileId.isNotEmpty) {
        final roleRef = _firestore.collection(roleCol).doc(profileId);
        batch.set(
          roleRef,
          {
            'verified': false,
            'verificationStatus': 'rejected',
            'status': 'rejected',
            'rejectionReason': reason.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('rejectProfile error: $e');
      return false;
    }
  }
}
