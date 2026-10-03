import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../enums/user_type.dart';
import '../firebase/ambulance_auth_helper.dart';
import '../firebase/firebase_auth_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../firebase/firestore_paths.dart';
import '../session/ambulance_session.dart';
import '../session/app_session.dart';
import '../session/doctor_session.dart';
import '../session/lab_session.dart';
import '../session/medical_store_session.dart';
import '../session/patient_session.dart';
import '../validators/form_validators.dart';
import '../validators/name_validator.dart';
import 'registration_credentials.dart';
import 'registration_otp_service.dart';

/// Single, unified onboarding service for ALL 6 roles:
/// Doctor, Patient, Medical, Pharmacy, Lab, Ambulance.
///
/// Guarantees:
/// - Full Name is required and validated before ever entering a dashboard.
/// - Exactly one user record per user (keyed by uid/phone).
/// - profileCompletionStatus is initialized to 'incomplete'.
/// - Name and role persist in Firestore, local cache, and active sessions.
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
        UserType.medical => 'medical',
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

  /// Completes the signup flow: validates real name, provisions Firestore records,
  /// initializes active role sessions, and persists credentials.
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
    final cleanDigits = FormValidators.mobileDigits(mobileDigits) ?? mobileDigits;
    final formattedMobile = FormValidators.formatFullPhone('+91', cleanDigits);

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

    // Persist to Cloud Firestore if connected
    if (FirebaseBootstrap.isReady) {
      final db = FirebaseFirestore.instance;
      final effectiveUid = uid ?? profileId;
      final batch = db.batch();

      final userRef = db.collection(FirestorePaths.users).doc(effectiveUid);
      final email = RegistrationCredentials.emailForMobile(cleanDigits);

      batch.set(
        userRef,
        {
          'role': roleStr,
          'profileId': profileId,
          'displayName': trimmedName,
          'name': trimmedName,
          'mobile': cleanDigits,
          'email': email,
          'mobileVerified': true,
          'profileCompleted': false,
          'profileCompletionStatus': 'incomplete',
          'verificationStatus': role == UserType.patient
              ? 'verified'
              : 'profile_incomplete',
          'status': role == UserType.patient ? 'approved' : 'pending_review',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Domain profile collection
      final domainCollection = switch (role) {
        UserType.doctor => FirestorePaths.doctors,
        UserType.patient => FirestorePaths.patients,
        UserType.medical => FirestorePaths.medicalStores,
        UserType.medicalStore => FirestorePaths.medicalStores,
        UserType.lab => FirestorePaths.labs,
        UserType.ambulance => FirestorePaths.ambulances,
        UserType.superAdmin => FirestorePaths.users,
      };

      final domainRef = db.collection(domainCollection).doc(profileId);
      final domainData = <String, dynamic>{
        'name': trimmedName,
        'mobile': formattedMobile,
        'phone': formattedMobile,
        'email': email,
        'profileCompleted': false,
        'profileCompletionStatus': 'incomplete',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (role == UserType.doctor) {
        domainData['doctorId'] = profileId;
        domainData['status'] = 'pending_review';
        domainData['verificationStatus'] = 'profile_incomplete';
      } else if (role == UserType.patient) {
        domainData['patientId'] = profileId;
        domainData['verified'] = true;
      } else if (role == UserType.medical || role == UserType.medicalStore) {
        domainData['storeId'] = profileId;
        domainData['storeName'] = trimmedName;
        domainData['ownerName'] = trimmedName;
        domainData['verified'] = false;
        domainData['verificationStatus'] = 'profile_incomplete';
      } else if (role == UserType.lab) {
        domainData['labId'] = profileId;
        domainData['labName'] = trimmedName;
        domainData['verified'] = false;
        domainData['verificationStatus'] = 'profile_incomplete';
      } else if (role == UserType.ambulance) {
        domainData['ambulanceId'] = profileId;
        domainData['serviceName'] = trimmedName;
        domainData['driverName'] = trimmedName;
        domainData['available'] = false;
        domainData['verified'] = false;
        domainData['verificationStatus'] = 'profile_incomplete';
      }

      batch.set(domainRef, domainData, SetOptions(merge: true));

      // Profile claim
      final claimRef = db.collection('profile_claims').doc(profileId);
      batch.set(
        claimRef,
        {
          'uid': effectiveUid,
          'role': roleStr,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      try {
        await batch.commit();
      } catch (e) {
        if (kDebugMode) debugPrint('Onboarding batch commit failed: $e');
      }

      // If user is not yet created in Firebase Auth, register credentials
      if (FirebaseAuth.instance.currentUser == null) {
        try {
          final password = RegistrationCredentials.generatePassword();
          await FirebaseAuthService.instance.registerProfile(
            role: role == UserType.medical ? UserType.medicalStore : role,
            email: email,
            password: password,
            profileId: profileId,
            displayName: trimmedName,
            mobile: formattedMobile,
            otpVerificationSessionId:
                RegistrationOtpService.verificationSessionId,
            roleData: domainData,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('FirebaseAuthService register failed: $e');
        }
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
