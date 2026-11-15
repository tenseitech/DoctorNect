import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/verification_lifecycle.dart' show RoleVerificationController, VerificationStage;
import '../enums/user_type.dart';
import '../supabase/supabase_bootstrap.dart';
import '../supabase/supabase_stream_table.dart';
import '../util/map_date_time.dart';

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
    final roleStr =
        (data['role'] as String? ?? data['user_role'] as String? ?? 'patient')
            .toLowerCase();
    final role = switch (roleStr) {
      'doctor' => UserType.doctor,
      'medicalstore' || 'pharmacy' || 'medical_store' => UserType.medicalStore,
      'lab' => UserType.lab,
      'ambulance' => UserType.ambulance,
      'super_admin' || 'superadmin' => UserType.superAdmin,
      _ => UserType.patient,
    };

    final verified = data['verified'] == true;
    final statusStr = data['verification_status'] as String? ??
        data['verificationStatus'] as String? ??
        data['status'] as String? ??
        (verified ? 'verified' : 'registered');

    return VerificationApplicant(
      uid: uid,
      displayName: data['display_name'] as String? ??
          data['displayName'] as String? ??
          'New Professional',
      email: data['email'] as String? ?? '',
      mobile: data['mobile'] as String? ?? data['phone'] as String? ?? '',
      role: role,
      profileId:
          data['profile_id'] as String? ?? data['profileId'] as String? ?? '',
      verificationStatus: verified
          ? VerificationStage.verified
          : VerificationStage.fromString(statusStr),
      verified: verified,
      rejectionReason: data['rejection_reason'] as String? ??
          data['rejectionReason'] as String?,
      submittedAt: parseMapDateTime(
        data['submitted_at'] ?? data['submittedAt'],
      ),
      createdAt: parseMapDateTime(data['created_at'] ?? data['createdAt']),
      roleData: roleData,
    );
  }
}

/// Service handling Super Admin verification workflows.
class SuperAdminVerificationService {
  SuperAdminVerificationService._();

  static final SuperAdminVerificationService instance =
      SuperAdminVerificationService._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  @visibleForTesting
  static Stream<List<VerificationApplicant>>? debugApplicantsStreamOverride;

  Stream<List<VerificationApplicant>> streamApplicants({
    UserType? roleFilter,
    VerificationStage? stageFilter,
    int limit = 150,
  }) {
    if (debugApplicantsStreamOverride != null) {
      return debugApplicantsStreamOverride!;
    }
    if (!SupabaseBootstrap.isReady) {
      return Stream.value(const []);
    }

    Stream<List<Map<String, dynamic>>> rows;
    if (SupabaseBootstrap.isProduction) {
      rows = streamTable(
        table: 'users',
        primaryKey: ['id'],
      );
    } else {
      rows = _client.from('users').stream(primaryKey: ['id']);
    }

    return rows.map((snapshot) {
      final list = <VerificationApplicant>[];
      for (final data in snapshot) {
        final roleStr = (data['role'] as String? ?? '').toLowerCase();
        if (roleStr == 'patient' || roleStr.isEmpty) continue;

        final uid = data['id'] as String? ?? data['firebase_uid'] as String? ?? '';
        if (uid.isEmpty) continue;

        final applicant = VerificationApplicant.fromMap(uid, data);
        if (roleFilter != null && applicant.role != roleFilter) continue;
        if (stageFilter != null) {
          final matches = stageFilter.isIncomplete
              ? applicant.verificationStatus.isIncomplete
              : applicant.verificationStatus == stageFilter;
          if (!matches) continue;
        }
        list.add(applicant);
        if (list.length >= limit) break;
      }

      list.sort((a, b) {
        final aTime = a.submittedAt ?? a.createdAt ?? DateTime(2000);
        final bTime = b.submittedAt ?? b.createdAt ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      return list;
    });
  }

  String? _roleTable(UserType role) {
    return switch (role) {
      UserType.doctor => 'doctors',
      UserType.medicalStore => 'medical_stores',
      UserType.lab => 'labs',
      UserType.ambulance => 'ambulances',
      _ => null,
    };
  }

  String? _rolePk(UserType role) {
    return switch (role) {
      UserType.doctor => 'doctor_id',
      UserType.medicalStore => 'store_id',
      UserType.lab => 'lab_id',
      UserType.ambulance => 'ambulance_id',
      _ => null,
    };
  }

  Future<Map<String, dynamic>> fetchRoleDetails(
    UserType role,
    String profileId,
  ) async {
    if (profileId.isEmpty || !SupabaseBootstrap.isReady) return {};
    final table = _roleTable(role);
    final pk = _rolePk(role);
    if (table == null || pk == null) return {};

    try {
      final res = await _client.from(table).select().eq(pk, profileId).maybeSingle();
      if (res == null) return {};
      return Map<String, dynamic>.from(res);
    } catch (e) {
      if (kDebugMode) debugPrint('fetchRoleDetails error: $e');
      return {};
    }
  }

  Future<bool> _updateVerification({
    required String uid,
    required UserType role,
    required String profileId,
    required Map<String, dynamic> userFields,
    required Map<String, dynamic> roleFields,
  }) async {
    if (!SupabaseBootstrap.isReady) return false;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client.from('users').update({
        ...userFields,
        'updated_at': now,
      }).or('id.eq.$uid,firebase_uid.eq.$uid');

      final table = _roleTable(role);
      final pk = _rolePk(role);
      if (table != null && pk != null && profileId.isNotEmpty) {
        await _client.from(table).update({
          ...roleFields,
          'updated_at': now,
        }).eq(pk, profileId);
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('verification update error: $e');
      return true;
    }
  }

  Future<bool> approveProfile({
    required String uid,
    required UserType role,
    required String profileId,
  }) async {
    RoleVerificationController.instance.markVerified(role);
    return _updateVerification(
      uid: uid,
      role: role,
      profileId: profileId,
      userFields: {
        'verified': true,
        'verification_status': 'verified',
        'status': 'approved',
        'rejection_reason': null,
        'verified_at': DateTime.now().toUtc().toIso8601String(),
      },
      roleFields: {
        'verified': true,
        'verification_status': 'verified',
        'status': 'approved',
        'rejection_reason': null,
        'verified_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

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
    return _updateVerification(
      uid: uid,
      role: role,
      profileId: profileId,
      userFields: {
        'verified': false,
        'verification_status': 'revision_requested',
        'status': 'revision_requested',
        'rejection_reason': reason.trim(),
      },
      roleFields: {
        'verified': false,
        'verification_status': 'revision_requested',
        'status': 'revision_requested',
        'rejection_reason': reason.trim(),
      },
    );
  }

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
    return _updateVerification(
      uid: uid,
      role: role,
      profileId: profileId,
      userFields: {
        'verified': false,
        'verification_status': 'profile_incomplete',
        'status': 'rejected',
        'rejection_reason': reason.trim(),
      },
      roleFields: {
        'verified': false,
        'verification_status': 'profile_incomplete',
        'status': 'rejected',
        'rejection_reason': reason.trim(),
      },
    );
  }
}