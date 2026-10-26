import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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
          .eq('id', uid)
          .maybeSingle();

      if (res == null) return null;
      return _fromRow(uid, res);
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
          'verified': !requiresVerification,
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
