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
      'medicalstore' ||
      'medical_store' ||
      'pharmacy' ||
      'medical' =>
        UserType.medicalStore,
      'lab' => UserType.lab,
      'ambulance' => UserType.ambulance,
      'super_admin' || 'superadmin' || 'admin' => UserType.superAdmin,
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

/// Result holder for cursor-based paginated applicant queries.
class PaginatedApplicantsResult {
  const PaginatedApplicantsResult({
    required this.applicants,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<VerificationApplicant> applicants;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}

/// Service handling Super Admin verification workflows.
class SuperAdminVerificationService {
  SuperAdminVerificationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static final SuperAdminVerificationService instance =
      SuperAdminVerificationService();

  final FirebaseFirestore _firestore;

  /// Stream list of pending verification applicants (the verification queue).
  ///
  /// Uses a server-side where-filter on [verificationStatus] so that ALL pending
  /// applicants are returned regardless of total user count in the collection.
  /// Patient and Admin/Super Admin accounts are never returned as applicants.
  Stream<List<VerificationApplicant>> streamApplicants({
    UserType? roleFilter,
    VerificationStage? stageFilter,
  }) {
    Query<Map<String, dynamic>> query =
        _firestore.collection(FirestorePaths.users);

    if (stageFilter == null ||
        stageFilter == VerificationStage.submittedForVerification) {
      // Pending verification queue: server-side where-filter, NO blanket limit.
      query = query.where(
        'verificationStatus',
        whereIn: const [
          'submitted_for_verification',
          'pending_review',
          'pending',
        ],
      );
    } else if (stageFilter == VerificationStage.registered) {
      query = query.where(
        'verificationStatus',
        whereIn: const ['registered', 'profile_incomplete'],
      );
    } else {
      query = query.where(
        'verificationStatus',
        isEqualTo: stageFilter.wireValue,
      );
    }

    return query.snapshots().map((snapshot) {
      final list = <VerificationApplicant>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final applicant = VerificationApplicant.fromMap(doc.id, data);
        if (applicant.role == UserType.patient ||
            applicant.role == UserType.superAdmin) {
          continue;
        }
        if (roleFilter != null && applicant.role != roleFilter) {
          continue;
        }
        if (stageFilter != null) {
          final matches = stageFilter.isIncomplete
              ? applicant.verificationStatus.isIncomplete
              : applicant.verificationStatus == stageFilter;
          if (!matches) continue;
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

  /// Cursor-based paginated fetch of applicants (page size 50 by default).
  /// Used for non-pending queues (already verified, rejected, history, etc.).
  Future<PaginatedApplicantsResult> fetchApplicantsPage({
    UserType? roleFilter,
    VerificationStage? stageFilter,
    DocumentSnapshot<Map<String, dynamic>>? startAfterDocument,
    int pageSize = 50,
  }) async {
    Query<Map<String, dynamic>> query =
        _firestore.collection(FirestorePaths.users);

    if (stageFilter != null) {
      if (stageFilter == VerificationStage.submittedForVerification) {
        query = query.where(
          'verificationStatus',
          whereIn: const [
            'submitted_for_verification',
            'pending_review',
            'pending',
          ],
        );
      } else if (stageFilter == VerificationStage.registered) {
        query = query.where(
          'verificationStatus',
          whereIn: const ['registered', 'profile_incomplete'],
        );
      } else {
        query = query.where(
          'verificationStatus',
          isEqualTo: stageFilter.wireValue,
        );
      }
    } else {
      // History / All Statuses: Filter by professional roles when no role filter is set
      if (roleFilter == null) {
        query = query.where(
          'role',
          whereIn: const [
            'doctor',
            'medicalstore',
            'medicalStore',
            'pharmacy',
            'medical',
            'lab',
            'ambulance',
          ],
        );
      }
    }

    if (roleFilter != null) {
      final roleKey = switch (roleFilter) {
        UserType.doctor => 'doctor',
        UserType.lab => 'lab',
        UserType.ambulance => 'ambulance',
        _ => null,
      };
      if (roleKey != null) {
        query = query.where('role', isEqualTo: roleKey);
      }
    }

    if (startAfterDocument != null) {
      query = query.startAfterDocument(startAfterDocument);
    }

    final snap = await query.limit(pageSize).get();

    final applicants = <VerificationApplicant>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final applicant = VerificationApplicant.fromMap(doc.id, data);
      if (applicant.role == UserType.patient ||
          applicant.role == UserType.superAdmin) {
        continue;
      }
      if (roleFilter != null && applicant.role != roleFilter) {
        continue;
      }
      if (stageFilter != null) {
        final matches = stageFilter.isIncomplete
            ? applicant.verificationStatus.isIncomplete
            : applicant.verificationStatus == stageFilter;
        if (!matches) continue;
      }
      applicants.add(applicant);
    }

    applicants.sort((a, b) {
      final aTime = a.submittedAt ?? a.createdAt ?? DateTime(2000);
      final bTime = b.submittedAt ?? b.createdAt ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    final lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
    final hasMore = snap.docs.length >= pageSize;

    return PaginatedApplicantsResult(
      applicants: applicants,
      lastDocument: lastDoc,
      hasMore: hasMore,
    );
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
    RoleVerificationController.instance.markVerified(role);
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
          SetOptions(merge: true));

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
            SetOptions(merge: true));
      }

      await batch.commit();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('approveProfile error: $e');
      return true;
    }
  }

  /// Request corrections/revisions with a reason.
  Future<bool> requestRevision({
    required String uid,
    required UserType role,
    required String profileId,
    required String reason,
  }) async {
    RoleVerificationController.instance.markRejected(
      role,
      reason,
      stage: VerificationStage.revisionRequested,
    );
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
          SetOptions(merge: true));

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
            SetOptions(merge: true));
      }

      await batch.commit();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('requestRevision error: $e');
      return true;
    }
  }

  /// Reject application with reason — sends the user back to `profile_incomplete` with a reason shown.
  Future<bool> rejectProfile({
    required String uid,
    required UserType role,
    required String profileId,
    required String reason,
  }) async {
    RoleVerificationController.instance.markRejected(
      role,
      reason,
      stage: VerificationStage.profileIncomplete,
    );
    try {
      final batch = _firestore.batch();
      final userRef = _firestore.collection(FirestorePaths.users).doc(uid);

      batch.set(
          userRef,
          {
            'verified': false,
            'verificationStatus': 'profile_incomplete',
            'status': 'rejected',
            'rejectionReason': reason.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

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
              'verificationStatus': 'profile_incomplete',
              'status': 'rejected',
              'rejectionReason': reason.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }

      await batch.commit();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('rejectProfile error: $e');
      return true;
    }
  }
}
