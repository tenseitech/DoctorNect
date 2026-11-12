import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../enums/user_type.dart';
import '../../supabase/repositories/supabase_user_repository.dart';
import '../models/medibond_user_profile.dart';

class UserRepository {
  UserRepository._();

  static final UserRepository instance = UserRepository._();

  @visibleForTesting
  static SupabaseUserRepository? debugSupabaseUserRepository;

  /// Legacy test hook — Firestore user reads are removed; ignored at runtime.
  @visibleForTesting
  static dynamic debugFirestore;

  SupabaseUserRepository get _repo =>
      debugSupabaseUserRepository ?? SupabaseUserRepository.instance;

  Future<DoctorNectUserProfile?> fetchProfile(
    String uid, {
    bool preferCache = true,
  }) =>
      _repo.fetchProfile(uid, preferCache: preferCache);

  Future<void> createProfile({
    required User user,
    required UserType role,
    required String profileId,
    required String displayName,
    String? mobile,
    bool mobileVerified = false,
    Map<String, dynamic>? roleData,
  }) =>
      _repo.createProfile(
        user: user,
        role: role,
        profileId: profileId,
        displayName: displayName,
        mobile: mobile,
        mobileVerified: mobileVerified,
        roleData: roleData,
      );

  Future<DoctorNectUserProfile?> repairMissingProfile({
    required User user,
    required UserType expectedRole,
  }) =>
      _repo.repairMissingProfile(user: user, expectedRole: expectedRole);

  Future<DoctorNectUserProfile?> relinkOAuthProfileByEmail({
    required User user,
    required UserType expectedRole,
  }) =>
      _repo.relinkOAuthProfileByEmail(user: user, expectedRole: expectedRole);

  Future<DoctorNectUserProfile?> findProfileByEmail(String email) =>
      _repo.findProfileByEmail(email);

  Future<String?> findEmailByMobile({
    required UserType role,
    required String mobile,
  }) =>
      _repo.findEmailByMobile(role: role, mobile: mobile);

  Future<DoctorNectUserProfile?> findProfileByMobile({
    required UserType role,
    required String mobile,
  }) =>
      _repo.findProfileByMobile(role: role, mobile: mobile);

  Future<UserType?> findRoleWithMobile(String mobile) =>
      _repo.findRoleWithMobile(mobile);

  Future<void> ensureDemoProfile({
    required User user,
    required UserType role,
    required String profileId,
    required String displayName,
    String? mobile,
    Map<String, dynamic>? roleData,
  }) =>
      _repo.ensureDemoProfile(
        user: user,
        role: role,
        profileId: profileId,
        displayName: displayName,
        mobile: mobile,
        roleData: roleData,
      );

  Future<String?> checkDuplicateAccountExists({
    required String email,
    required String? mobile,
    required UserType currentRole,
  }) =>
      _repo.checkDuplicateAccountExists(
        email: email,
        mobile: mobile,
        currentRole: currentRole,
      );

  Future<String?> checkDoctorCouncilNumberExists({
    required String councilNumber,
    required String doctorId,
  }) =>
      _repo.checkDoctorCouncilNumberExists(
        councilNumber: councilNumber,
        doctorId: doctorId,
      );

  Future<String> deletePendingAuthUser(User user) =>
      _repo.deletePendingAuthUser(user);

  Future<String?> validateNewRegistration({
    required UserType role,
    required String email,
    required String? mobile,
    required String profileId,
    Map<String, dynamic>? roleData,
  }) =>
      _repo.validateNewRegistration(
        role: role,
        email: email,
        mobile: mobile,
        profileId: profileId,
        roleData: roleData,
      );

  Future<void> deleteAccount({required User user}) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable('deleteMyAccount');
    final result = await callable.call<Map<String, dynamic>>({});
    final ok = result.data['ok'] == true;
    if (!ok) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Could not delete account. Please try again.',
      );
    }
  }
}
