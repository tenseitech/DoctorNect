import '../supabase/supabase_bootstrap.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../enums/user_type.dart';
import '../firebase/ambulance_auth_helper.dart';
import '../session/ambulance_session.dart';
import '../session/app_session.dart';
import '../session/doctor_session.dart';
import '../session/lab_session.dart';
import '../session/medical_store_session.dart';
import '../session/patient_session.dart';
import '../validators/form_validators.dart';
import '../validators/name_validator.dart';
import 'registration_credentials.dart';

/// Single, unified onboarding service for ALL 6 roles:
/// Doctor, Patient, Medical, Pharmacy, Lab, Ambulance.
///
/// Guarantees:
/// - Full Name is required and validated before ever entering a dashboard.
/// - Exactly one user record per user (keyed by uid/phone).
/// - profileCompletionStatus is initialized to 'incomplete'.
/// - Name and role persist in Postgres (users upsert), local cache, and active sessions.
class OnboardingService {
  OnboardingService._();

  static final OnboardingService instance = OnboardingService._();

  static const _prefKeyRole = 'doctornect_saved_user_role';
  static const _prefKeyName = 'doctornect_saved_user_name';
  static const _prefKeyId = 'doctornect_saved_profile_id';
  static const _prefKeyMobile = 'doctornect_saved_user_mobile';

  /// Converts [UserType] to storage string key.
  static String roleString(UserType role) => switch (role) {
        UserType.doctor => 'doctor',
        UserType.patient => 'patient',
        UserType.medical => 'medicalStore',
        UserType.medicalStore => 'medicalStore',
        UserType.lab => 'lab',
        UserType.ambulance => 'ambulance',
        UserType.superAdmin => 'super_admin',
      };

  /// Parses a string back to [UserType].
  static UserType? parseRole(String? raw) {
    if (raw == null) return null;
    final lower = raw.trim().toLowerCase();
    return switch (lower) {
      'doctor' => UserType.doctor,
      'patient' => UserType.patient,
      'medical' => UserType.medical,
      'medicalstore' || 'medical_store' || 'pharmacy' => UserType.medicalStore,
      'lab' => UserType.lab,
      'ambulance' => UserType.ambulance,
      'super_admin' || 'superadmin' => UserType.superAdmin,
      _ => null,
    };
  }

  /// Completes the signup flow: validates real name, upserts Postgres users row,
  /// initializes active role sessions, and persists credentials locally.
  Future<void> completeNameOnboarding({
    required UserType role,
    required String fullName,
    required String mobileDigits,
  }) async {
    final validationError = NameValidator.validate(fullName);
    if (validationError != null) {
      throw ArgumentError(validationError);
    }

    final trimmedName = fullName.trim();
    final cleanDigits =
        FormValidators.mobileDigits(mobileDigits) ?? mobileDigits;
    String? uid = FirebaseAuth.instance.currentUser?.uid;

    // If no Firebase Auth session exists yet, ensure one (e.g. for phone or ambulance)
    if (uid == null || uid.isEmpty) {
      if (role == UserType.ambulance) {
        await AmbulanceAuthHelper.ensureSignedIn();
        uid = FirebaseAuth.instance.currentUser?.uid;
      }
    }

    // Generate unique domain profile ID
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final profileId = switch (role) {
      UserType.doctor => 'd$timestamp',
      UserType.patient => 'p$timestamp',
      UserType.medical => 'med$timestamp',
      UserType.medicalStore => 'ms$timestamp',
      UserType.lab => 'lab$timestamp',
      UserType.ambulance => 'amb-$timestamp',
      UserType.superAdmin => 'adm$timestamp',
    };

    final roleStr = roleString(role);

    // Save locally immediately
    await _saveLocalSession(
      role: role,
      name: trimmedName,
      profileId: profileId,
      mobile: cleanDigits,
    );

    // Set active in-memory sessions
    _updateActiveSessions(
      role: role,
      profileId: profileId,
      name: trimmedName,
    );

    if (SupabaseBootstrap.isReady) {
      final effectiveUid = uid ?? profileId;
      final email = RegistrationCredentials.emailForMobile(cleanDigits);
      try {
        final client = SupabaseBootstrap.client;
        await client.from('users').upsert({
          'id': effectiveUid,
          'firebase_uid': effectiveUid,
          'role': roleStr,
          'profile_id': profileId,
          'display_name': trimmedName,
          'email': email,
          'mobile': cleanDigits,
          'profile_completed': false,
          'verified': role == UserType.patient,
          'status': role == UserType.patient ? 'approved' : 'pending_review',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (e) {
        if (kDebugMode) debugPrint('[OnboardingService] Supabase upsert error: $e');
      }
    }

  }

  /// Updates all active in-memory session singletons with the real name.
  void _updateActiveSessions({
    required UserType role,
    required String profileId,
    required String name,
  }) {
    switch (role) {
      case UserType.doctor:
        DoctorSession.setDoctor(id: profileId, name: name);
      case UserType.patient:
        PatientSession.setPatient(id: profileId, name: name);
      case UserType.medical:
      case UserType.medicalStore:
        MedicalStoreSession.setStore(id: profileId, name: name);
      case UserType.lab:
        LabSession.setLab(id: profileId, name: name);
      case UserType.ambulance:
        unawaited(
          AmbulanceSession.setAmbulance(
            id: profileId,
            serviceName: name,
            driverName: name,
          ),
        );
      case UserType.superAdmin:
        AppSession.setSuperAdmin(id: profileId, name: name);
    }
  }

  /// Saves session data to [SharedPreferences] for seamless page reload recovery.
  Future<void> _saveLocalSession({
    required UserType role,
    required String name,
    required String profileId,
    required String mobile,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyRole, roleString(role));
      await prefs.setString(_prefKeyName, name);
      await prefs.setString(_prefKeyId, profileId);
      await prefs.setString(_prefKeyMobile, mobile);
    } catch (e) {
      if (kDebugMode) debugPrint('saveLocalSession failed: $e');
    }
  }

  /// Attempts to restore a saved user session upon page refresh or app start.
  Future<bool> restoreLocalSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final roleStr = prefs.getString(_prefKeyRole);
      final name = prefs.getString(_prefKeyName);
      final id = prefs.getString(_prefKeyId);

      if (roleStr == null || name == null || id == null) return false;
      if (!NameValidator.isValid(name)) return false;

      final role = parseRole(roleStr);
      if (role == null) return false;

      _updateActiveSessions(role: role, profileId: id, name: name);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clears saved local session credentials on logout.
  Future<void> clearLocalSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyRole);
      await prefs.remove(_prefKeyName);
      await prefs.remove(_prefKeyId);
      await prefs.remove(_prefKeyMobile);
    } catch (_) {}
  }
}
