import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../auth/demo_auth_config.dart';
import '../../enums/user_type.dart';
import '../../firebase/models/medibond_user_profile.dart';
import '../../validators/form_validators.dart';
import '../supabase_bootstrap.dart';
import '../supabase_stream_table.dart';

/// Supabase Repository for User Profile Management.
/// Replaces Firestore `users/{uid}` operations while preserving the interface.
class SupabaseUserRepository {
  SupabaseUserRepository._();

  static final SupabaseUserRepository instance = SupabaseUserRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  /// Fetches a user profile from PostgreSQL `public.users` by Firebase UID (`id`).
  Future<DoctorNectUserProfile?> fetchProfile(
    String uid, {
    bool preferCache = true,
  }) async {
    if (!SupabaseBootstrap.isReady || uid.isEmpty) return null;

    try {
      final res = await _client
          .from('users')
          .select()
          .or('id.eq.$uid,firebase_uid.eq.$uid')
          .maybeSingle();

      if (res == null) return null;
      final resolvedUid = res['id'] as String? ?? uid;
      return _fromRow(resolvedUid, res);
    } catch (_) {
      return null;
    }
  }

  /// Real-time stream of a user's profile via Supabase Realtime `.stream()`.
  /// Uses a single `.eq('id', uid)` filter on primary key `id`.
  Stream<DoctorNectUserProfile?> watchProfile(String uid) {
    if (!SupabaseBootstrap.isReady || uid.isEmpty) {
      return const Stream.empty();
    }

    if (SupabaseBootstrap.isProduction) {
      return streamTable(
        table: 'users',
        primaryKey: ['id'],
        filterColumn: 'id',
        filterValue: uid,
      ).map((rows) {
        if (rows.isEmpty) return null;
        return _fromRow(uid, rows.first);
      });
    }

    return _client
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .map((rows) {
          if (rows.isEmpty) return null;
          return _fromRow(uid, rows.first);
        });
  }

  /// Creates a new profile directly in Supabase `public.users`.
  Future<void> createProfile({
    required User user,
    required UserType role,
    required String profileId,
    required String displayName,
    String? mobile,
    bool mobileVerified = false,
    Map<String, dynamic>? roleData,
  }) async {
    final normalizedMobile =
        mobile == null ? null : FormValidators.mobileDigits(mobile);
    final isDemoDoctor = role == UserType.doctor &&
        (DemoAuthConfig.isDemoDoctorPhone(normalizedMobile) ||
            DemoAuthConfig.isDemoDoctorPhone(mobile));
    final requiresVerification = (role == UserType.doctor ||
            role == UserType.medical ||
            role == UserType.medicalStore ||
            role == UserType.lab ||
            role == UserType.ambulance) &&
        !isDemoDoctor;

    final roleString = switch (role) {
      UserType.superAdmin => 'super_admin',
      UserType.doctor => 'doctor',
      UserType.medical => 'medicalStore',
      UserType.medicalStore => 'medicalStore',
      UserType.patient => 'patient',
      UserType.lab => 'lab',
      UserType.ambulance => 'ambulance',
    };

    final email = (user.email?.isNotEmpty == true
            ? user.email
            : roleData?['email'] as String?)
        ?.trim()
        .toLowerCase() ??
        '';

    final userPayload = {
      'id': user.uid,
      'firebase_uid': user.uid,
      'role': roleString,
      'profile_id': profileId,
      'display_name': displayName,
      'email': email.isEmpty ? '${user.uid}@auth.doctornect.com' : email,
      if (normalizedMobile != null) 'mobile': normalizedMobile,
      'profile_completed': isDemoDoctor ? true : false,
      'verified': !requiresVerification,
      'status': requiresVerification ? 'pending_review' : 'approved',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _client.from('users').upsert(userPayload, onConflict: 'id');

    // Provision corresponding domain role record if payload provided
    if (roleData != null) {
      if (role == UserType.doctor) {
        await _client.from('doctors').upsert({
          'doctor_id': profileId,
          'owner_uid': user.uid,
          'name': displayName,
          'email': email,
          'mobile': normalizedMobile ?? '',
          'specialization': roleData['specialization'] ?? 'General Physician',
          'qualification': roleData['qualification'] ?? 'MBBS',
          'verified': false,
          'profile_completed': isDemoDoctor ? true : false,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'doctor_id');
      } else if (role == UserType.patient) {
        await _client.from('patients').upsert({
          'patient_id': profileId,
          'owner_uid': user.uid,
          'name': displayName,
          'mobile': normalizedMobile ?? '',
          'email': email,
          'profile_completed': isDemoDoctor ? true : false,
          'verified': true,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'patient_id');
      }
    }
  }

  /// Updates profile fields in `public.users`.
  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {
    if (!SupabaseBootstrap.isReady || uid.isEmpty) return;

    final updatePayload = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (data.containsKey('displayName')) {
      updatePayload['display_name'] = data['displayName'];
    }
    if (data.containsKey('mobile')) {
      updatePayload['mobile'] = data['mobile'];
    }
    if (data.containsKey('profileCompleted')) {
      updatePayload['profile_completed'] = data['profileCompleted'];
    }
    if (data.containsKey('photoUrl')) {
      updatePayload['photo_url'] = data['photoUrl'];
    }
    if (data.containsKey('photoS3Key')) {
      updatePayload['photo_s3_key'] = data['photoS3Key'];
    }

    await _client.from('users').update(updatePayload).eq('id', uid);
  }

  Future<DoctorNectUserProfile?> repairMissingProfile({
    required User user,
    required UserType expectedRole,
  }) async {
    final existing = await fetchProfile(user.uid, preferCache: false);
    if (existing != null) return existing;
    if (!SupabaseBootstrap.isReady) return null;

    if (expectedRole == UserType.superAdmin) return null;

    try {
      final row = await _fetchRoleRowForRepair(expectedRole, user.uid);
      if (row == null) return null;

      final profileId = _profileIdFromRoleRow(expectedRole, row);
      final displayName = _displayNameFromRoleRow(expectedRole, row);
      final roleString = _roleString(expectedRole);
      final email = _normalizeEmail(user.email) ??
          _normalizeEmail(row['email'] as String?);

      await _client.from('users').upsert({
        'id': user.uid,
        'firebase_uid': user.uid,
        'role': roleString,
        'profile_id': profileId,
        'display_name': displayName,
        'email': email ?? '${user.uid}@auth.doctornect.com',
        if (row['mobile'] is String) 'mobile': row['mobile'],
        if (row['phone'] is String) 'mobile': row['phone'],
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');

      return await fetchProfile(user.uid, preferCache: false);
    } catch (_) {
      return null;
    }
  }

  Future<DoctorNectUserProfile?> findProfileByEmail(String email) async {
    final normalized = _normalizeEmail(email);
    if (normalized == null || normalized.isEmpty) return null;
    for (final candidate in _emailCandidates(normalized)) {
      try {
        final res = await _client
            .from('users')
            .select('id')
            .eq('email', candidate)
            .limit(1)
            .maybeSingle();
        if (res != null) {
          return await fetchProfile(res['id'] as String, preferCache: false);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> findEmailByMobile({
    required UserType role,
    required String mobile,
  }) async {
    final digits = FormValidators.mobileDigits(mobile);
    if (digits == null || !SupabaseBootstrap.isReady) return null;
    final roleValue = _roleString(role);
    final candidates = <String>{digits, '+91$digits', '91$digits', '0$digits'};
    for (final candidate in candidates) {
      try {
        final res = await _client
            .from('users')
            .select('email')
            .eq('role', roleValue)
            .eq('mobile', candidate)
            .limit(1)
            .maybeSingle();
        final email = res?['email'] as String?;
        if (email != null && email.trim().isNotEmpty) return email.trim();
      } catch (_) {}
    }
    return null;
  }

  Future<DoctorNectUserProfile?> findProfileByMobile({
    required UserType role,
    required String mobile,
  }) async {
    final digits = FormValidators.registrationMobileDigits(mobile) ??
        FormValidators.mobileDigits(mobile) ??
        mobile.trim();
    if (digits.isEmpty || !SupabaseBootstrap.isReady) return null;

    final candidates = _buildMobileCandidates(mobile);
    final roleStr = _roleString(role);
    for (final candidate in candidates) {
      try {
        final res = await _client
            .from('users')
            .select('id')
            .eq('role', roleStr)
            .eq('mobile', candidate)
            .limit(1)
            .maybeSingle();
        if (res != null) {
          return await fetchProfile(res['id'] as String, preferCache: true);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<UserType?> findRoleWithMobile(String mobile) =>
      _findRoleWithMobile(
        FormValidators.registrationMobileDigits(mobile) ??
            FormValidators.mobileDigits(mobile) ??
            mobile.trim(),
      );

  Future<void> ensureDemoProfile({
    required User user,
    required UserType role,
    required String profileId,
    required String displayName,
    String? mobile,
    Map<String, dynamic>? roleData,
  }) async {
    final existing = await fetchProfile(user.uid);
    if (existing != null) return;
    await createProfile(
      user: user,
      role: role,
      profileId: profileId,
      displayName: displayName,
      mobile: mobile,
      roleData: roleData,
    );
  }

  Future<String?> checkDuplicateAccountExists({
    required String email,
    required String? mobile,
    required UserType currentRole,
  }) async {
    try {
      final normEmail = _normalizeEmail(email);
      if (normEmail != null && normEmail.isNotEmpty) {
        final existingRole = await _findRoleWithEmail(normEmail);
        if (existingRole != null) {
          if (existingRole != currentRole) {
            return 'An account with email "$normEmail" is already registered under the ${_roleLabel(existingRole)} role. Duplicate registration across different roles is not allowed.';
          }
          return 'An account with email "$normEmail" is already registered.';
        }
      }
      if (mobile != null && mobile.trim().isNotEmpty) {
        final digits = FormValidators.registrationMobileDigits(mobile) ??
            FormValidators.mobileDigits(mobile);
        if (digits != null && digits.isNotEmpty) {
          final existingRole = await _findRoleWithMobile(digits);
          if (existingRole != null) {
            if (existingRole != currentRole) {
              return 'An account with mobile number "$mobile" is already registered under the ${_roleLabel(existingRole)} role. Duplicate registration across different roles is not allowed.';
            }
            return 'An account with mobile number "$mobile" is already registered.';
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> checkDoctorCouncilNumberExists({
    required String councilNumber,
    required String doctorId,
  }) async {
    if (!SupabaseBootstrap.isReady) return null;
    try {
      final trimmed = councilNumber.trim();
      if (trimmed.isEmpty) return null;
      final res = await _client
          .from('doctors')
          .select('doctor_id')
          .eq('verified', true)
          .eq('council_number', trimmed)
          .limit(1)
          .maybeSingle();
      if (res != null && res['doctor_id'] != doctorId) {
        return 'This council registration number is already associated with another account.';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static const Duration orphanRegistrationMaxAge = Duration(minutes: 10);

  /// Optional test hook: return value ignored; runs before Firebase Auth delete.
  @visibleForTesting
  static Future<void> Function(String uid)? debugDeleteFreshOrphanProfileRows;

  /// Outcome of [deletePendingAuthUser] — used when finalize succeeded server-side
  /// but the client lost the HTTP response.
  static const pendingAuthDeleted = 'deleted';
  static const pendingAuthSkippedAlreadyVerified = 'skipped_already_verified';

  /// Reads `public.users` for rollback decisions (no side effects).
  ///
  /// Delete guards in [deleteFreshOrphanRegistrationProfile] (all must pass):
  /// 1. **Uid match:** row `id` or `firebase_uid` equals the signed-in [uid].
  /// 2. **Verified flags:** `mobile_verified` and `email_verified` are not true
  ///    (if either is true, row is treated as finalized — no delete).
  /// 3. **Age:** `created_at` parses and is within [orphanRegistrationMaxAge].
  /// 4. **Supabase ready:** [SupabaseBootstrap.isReady] and non-empty [uid].
  @visibleForTesting
  Future<Map<String, dynamic>?> loadRegistrationProfileRowForRollback(
    String uid,
  ) async {
    if (uid.isEmpty || !SupabaseBootstrap.isReady) return null;
    try {
      return await _client
          .from('users')
          .select(
            'id, firebase_uid, profile_id, role, created_at, mobile_verified, email_verified',
          )
          .or('id.eq.$uid,firebase_uid.eq.$uid')
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static Future<bool> Function(String uid)?
      debugIsRegistrationProfileAlreadyVerified;

  /// True when OTP finalize (or equivalent) already persisted on the profile row.
  Future<bool> isRegistrationProfileAlreadyVerified(String uid) async {
    if (debugIsRegistrationProfileAlreadyVerified != null) {
      return debugIsRegistrationProfileAlreadyVerified!(uid);
    }
    final row = await loadRegistrationProfileRowForRollback(uid);
    if (row == null) return false;
    return row['mobile_verified'] == true || row['email_verified'] == true;
  }

  bool _registrationProfileRowMatchesUid(String uid, Map<String, dynamic> row) {
    final rowId = row['id'] as String?;
    final firebaseUid = row['firebase_uid'] as String?;
    return rowId == uid || firebaseUid == uid;
  }

  /// Removes a fresh, unverified `public.users` row (and role table row) for [uid].
  /// See [loadRegistrationProfileRowForRollback] for guard list.
  Future<void> deleteFreshOrphanRegistrationProfile(String uid) async {
    if (uid.isEmpty || !SupabaseBootstrap.isReady) return;

    try {
      final row = await loadRegistrationProfileRowForRollback(uid);
      if (row == null) return;
      if (!_registrationProfileRowMatchesUid(uid, row)) return;

      final mobileVerified = row['mobile_verified'] == true;
      final emailVerified = row['email_verified'] == true;
      if (mobileVerified || emailVerified) return;

      final createdRaw = row['created_at'];
      DateTime? createdAt;
      if (createdRaw is String) {
        createdAt = DateTime.tryParse(createdRaw);
      } else if (createdRaw is DateTime) {
        createdAt = createdRaw;
      }
      if (createdAt == null) return;
      if (DateTime.now().difference(createdAt) > orphanRegistrationMaxAge) {
        return;
      }

      final profileId = (row['profile_id'] as String?)?.trim() ?? '';
      final role = (row['role'] as String?)?.trim().toLowerCase() ?? '';
      if (profileId.isNotEmpty && role == 'patient') {
        await _client.from('patients').delete().eq('patient_id', profileId);
      } else if (profileId.isNotEmpty && role == 'doctor') {
        await _client.from('doctors').delete().eq('doctor_id', profileId);
      }
      await _client.from('users').delete().eq('id', uid);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SupabaseUserRepository] deleteFreshOrphanRegistrationProfile failed: $e',
        );
      }
    }
  }

  /// Removes the Firebase Auth user created during an aborted registration attempt.
  /// Caller must still be signed in as [user] (same semantics as legacy Firestore path).
  ///
  /// Returns [pendingAuthSkippedAlreadyVerified] when the profile row already has
  /// `mobile_verified` or `email_verified` (e.g. finalize succeeded server-side).
  Future<String> deletePendingAuthUser(User user) async {
    final uid = user.uid;
    if (await isRegistrationProfileAlreadyVerified(uid)) {
      return pendingAuthSkippedAlreadyVerified;
    }
    if (debugDeleteFreshOrphanProfileRows != null) {
      await debugDeleteFreshOrphanProfileRows!(uid);
    } else {
      await deleteFreshOrphanRegistrationProfile(uid);
    }
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SupabaseUserRepository] deletePendingAuthUser failed: ${e.code}',
        );
      }
      rethrow;
    }
    return pendingAuthDeleted;
  }

  Future<String?> validateNewRegistration({
    required UserType role,
    required String email,
    required String? mobile,
    required String profileId,
    Map<String, dynamic>? roleData,
  }) async {
    final duplicateError = await checkDuplicateAccountExists(
      email: email,
      mobile: mobile,
      currentRole: role,
    );
    if (duplicateError != null) return duplicateError;
    if (role == UserType.doctor) {
      final councilNumber = roleData?['councilNumber'] as String?;
      if (councilNumber != null && councilNumber.trim().isNotEmpty) {
        return checkDoctorCouncilNumberExists(
          councilNumber: councilNumber,
          doctorId: profileId,
        );
      }
    }
    return null;
  }

  Future<DoctorNectUserProfile?> relinkOAuthProfileByEmail({
    required User user,
    required UserType expectedRole,
  }) async {
    final email = user.email?.trim();
    if (email == null || email.isEmpty || !SupabaseBootstrap.isReady) {
      return null;
    }
    final roleValue = _roleString(expectedRole);
    if (expectedRole == UserType.superAdmin) return null;

    for (final candidate in _emailCandidates(email)) {
      try {
        final userRow = await _client
            .from('users')
            .select()
            .eq('role', roleValue)
            .eq('email', candidate)
            .limit(1)
            .maybeSingle();
        if (userRow == null) continue;
        final profileId = userRow['profile_id'] as String? ?? '';
        if (profileId.isEmpty) continue;

        final normalizedEmail = _normalizeEmail(email)!;
        await _upsertRoleRowEmailLink(
          expectedRole,
          profileId,
          user.uid,
          normalizedEmail,
        );

        await _client.from('users').upsert({
          'id': user.uid,
          'firebase_uid': user.uid,
          'role': roleValue,
          'profile_id': profileId,
          'display_name': userRow['display_name'] ?? user.displayName ?? 'User',
          'email': normalizedEmail,
          if (userRow['mobile'] is String) 'mobile': userRow['mobile'],
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');

        return await fetchProfile(user.uid, preferCache: false);
      } catch (_) {}
    }
    return null;
  }

  Future<UserType?> _findRoleWithEmail(String email) async {
    final norm = _normalizeEmail(email);
    if (norm == null || norm.isEmpty || !SupabaseBootstrap.isReady) return null;
    for (final candidate in _emailCandidates(norm)) {
      try {
        final res = await _client
            .from('users')
            .select('role')
            .eq('email', candidate)
            .limit(1)
            .maybeSingle();
        if (res != null) {
          return _parseRoleString(res['role'] as String?);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<UserType?> _findRoleWithMobile(String digits) async {
    if (!SupabaseBootstrap.isReady) return null;
    for (final candidate in _buildMobileCandidates(digits)) {
      try {
        final res = await _client
            .from('users')
            .select('role, id')
            .eq('mobile', candidate)
            .limit(1)
            .maybeSingle();
        if (res != null) {
          return _parseRoleString(res['role'] as String?);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchRoleRowForRepair(
    UserType role,
    String uid,
  ) async {
    switch (role) {
      case UserType.doctor:
        return _client
            .from('doctors')
            .select()
            .eq('owner_uid', uid)
            .maybeSingle();
      case UserType.medical:
      case UserType.medicalStore:
        return _client
            .from('medical_stores')
            .select()
            .eq('owner_uid', uid)
            .maybeSingle();
      case UserType.patient:
        return _client
            .from('patients')
            .select()
            .eq('owner_uid', uid)
            .maybeSingle();
      case UserType.lab:
        return _client
            .from('labs')
            .select()
            .eq('owner_uid', uid)
            .maybeSingle();
      case UserType.ambulance:
        final byOwner = await _client
            .from('ambulances')
            .select()
            .eq('owner_uid', uid)
            .maybeSingle();
        if (byOwner != null) return byOwner;
        return _client
            .from('ambulances')
            .select()
            .eq('auth_uid', uid)
            .maybeSingle();
      case UserType.superAdmin:
        return null;
    }
  }

  Future<void> _upsertRoleRowEmailLink(
    UserType role,
    String profileId,
    String ownerUid,
    String normalizedEmail,
  ) async {
    final common = {
      'owner_uid': ownerUid,
      'email': normalizedEmail,
      'updated_at': DateTime.now().toIso8601String(),
    };
    switch (role) {
      case UserType.doctor:
        await _client.from('doctors').upsert({
          'doctor_id': profileId,
          ...common,
        }, onConflict: 'doctor_id');
      case UserType.medical:
      case UserType.medicalStore:
        await _client.from('medical_stores').upsert({
          'store_id': profileId,
          ...common,
        }, onConflict: 'store_id');
      case UserType.patient:
        await _client.from('patients').upsert({
          'patient_id': profileId,
          ...common,
        }, onConflict: 'patient_id');
      case UserType.lab:
        await _client.from('labs').upsert({
          'lab_id': profileId,
          ...common,
        }, onConflict: 'lab_id');
      case UserType.ambulance:
        await _client.from('ambulances').upsert({
          'ambulance_id': profileId,
          ...common,
        }, onConflict: 'ambulance_id');
      case UserType.superAdmin:
        break;
    }
  }

  String? _roleTable(UserType role) => switch (role) {
        UserType.doctor => 'doctors',
        UserType.medical || UserType.medicalStore => 'medical_stores',
        UserType.patient => 'patients',
        UserType.lab => 'labs',
        UserType.ambulance => 'ambulances',
        UserType.superAdmin => 'users',
      };

  String _roleIdColumn(UserType role) => switch (role) {
        UserType.doctor => 'doctor_id',
        UserType.medical || UserType.medicalStore => 'store_id',
        UserType.patient => 'patient_id',
        UserType.lab => 'lab_id',
        UserType.ambulance => 'ambulance_id',
        UserType.superAdmin => 'id',
      };

  String _roleString(UserType role) => switch (role) {
        UserType.superAdmin => 'super_admin',
        UserType.doctor => 'doctor',
        UserType.medical => 'medicalStore',
        UserType.medicalStore => 'medicalStore',
        UserType.patient => 'patient',
        UserType.lab => 'lab',
        UserType.ambulance => 'ambulance',
      };

  String _profileIdFromRoleRow(UserType role, Map<String, dynamic> row) =>
      switch (role) {
        UserType.superAdmin => row['id'] as String? ?? '',
        UserType.doctor => row['doctor_id'] as String? ?? '',
        UserType.medical || UserType.medicalStore =>
          row['store_id'] as String? ?? '',
        UserType.patient => row['patient_id'] as String? ?? '',
        UserType.lab => row['lab_id'] as String? ?? '',
        UserType.ambulance => row['ambulance_id'] as String? ?? '',
      };

  String _displayNameFromRoleRow(UserType role, Map<String, dynamic> row) =>
      switch (role) {
        UserType.superAdmin => 'Super Admin',
        UserType.doctor => row['name'] as String? ?? '',
        UserType.medical || UserType.medicalStore =>
          row['store_name'] as String? ?? row['name'] as String? ?? '',
        UserType.patient => row['name'] as String? ?? '',
        UserType.lab =>
          row['lab_name'] as String? ?? row['name'] as String? ?? '',
        UserType.ambulance =>
          row['service_name'] as String? ??
              row['driver_name'] as String? ??
              row['name'] as String? ??
              '',
      };

  Iterable<String> _emailCandidates(String email) sync* {
    final trimmed = email.trim();
    yield trimmed;
    yield trimmed.toLowerCase();
  }

  String? _normalizeEmail(String? email) {
    if (email == null) return null;
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty || trimmed.endsWith('@patient.doctornect.com')) {
      return null;
    }
    return trimmed;
  }

  Set<String> _buildMobileCandidates(String rawMobile) {
    final digits = FormValidators.registrationMobileDigits(rawMobile) ??
        FormValidators.mobileDigits(rawMobile) ??
        rawMobile.replaceAll(RegExp(r'[^\d]'), '');
    final candidates = <String>{};
    final trimmed = rawMobile.trim();
    if (trimmed.isNotEmpty) candidates.add(trimmed);
    if (digits.isNotEmpty) {
      candidates.add(digits);
      candidates.add('+91$digits');
      candidates.add('+91 $digits');
      candidates.add('+91-$digits');
      candidates.add('91$digits');
      candidates.add('0$digits');
    }
    return candidates;
  }

  UserType? _parseRoleString(String? roleStr) => switch (roleStr) {
        'super_admin' || 'superAdmin' => UserType.superAdmin,
        'doctor' => UserType.doctor,
        'patient' => UserType.patient,
        'medical' || 'medicalStore' => UserType.medicalStore,
        'lab' => UserType.lab,
        'ambulance' => UserType.ambulance,
        _ => null,
      };

  String _roleLabel(UserType role) => switch (role) {
        UserType.superAdmin => 'Super Admin',
        UserType.doctor => 'Doctor',
        UserType.patient => 'Patient',
        UserType.medical => 'Medical',
        UserType.medicalStore => 'Pharmacy / Medical Store',
        UserType.lab => 'Diagnostic Lab',
        UserType.ambulance => 'Ambulance Service',
      };

  DoctorNectUserProfile _fromRow(String uid, Map<String, dynamic> row) {
    final roleStr = row['role'] as String? ?? 'patient';
    final role = switch (roleStr) {
      'super_admin' || 'superAdmin' => UserType.superAdmin,
      'doctor' => UserType.doctor,
      'medicalStore' || 'medical' => UserType.medicalStore,
      'lab' => UserType.lab,
      'ambulance' => UserType.ambulance,
      _ => UserType.patient,
    };

    return DoctorNectUserProfile(
      uid: uid,
      role: role,
      profileId: row['profile_id'] as String? ?? '',
      displayName: row['display_name'] as String? ?? '',
      email: row['email'] as String? ?? '',
      mobile: row['mobile'] as String?,
      verificationStatus: (row['verified'] as bool? ?? false)
          ? 'verified'
          : (row['status'] as String? ?? 'pending_review'),
      rejectionReason: row['rejection_reason'] as String?,
      submittedAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'].toString())
          : null,
      photoUrl: row['photo_url'] as String?,
      photoKey: row['photo_key'] as String?,
      photoStorage: row['photo_storage'] as String?,
    );
  }
}
