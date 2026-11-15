import '../supabase/supabase_bootstrap.dart';
import 'package:flutter/foundation.dart';

import 'demo_auth_config.dart';
import 'verification_lifecycle.dart';
import '../enums/user_type.dart';

/// Tracks whether a non-patient user has completed their full profile (Supabase).
class ProfileCompletionService extends ChangeNotifier {
  ProfileCompletionService._();

  static final ProfileCompletionService instance = ProfileCompletionService._();

  bool _isComplete = true;

  bool get isComplete => _isComplete;

  String? lastError;

  Future<void> refreshForUser({
    required UserType role,
    required String uid,
    String? profileId,
  }) async {
    lastError = null;
    if (role.isPatient) {
      _isComplete = true;
      notifyListeners();
      return;
    }

    if (!SupabaseBootstrap.isReady || uid.isEmpty) {
      return;
    }

    try {
      final client = SupabaseBootstrap.client;
      final res = await client
          .from('users')
          .select('profile_completed')
          .or('id.eq.$uid,firebase_uid.eq.$uid')
          .maybeSingle();
      if (res != null && res['profile_completed'] is bool) {
        _isComplete = res['profile_completed'] as bool;
        notifyListeners();
        return;
      }

      if (role.isAmbulance && profileId != null && profileId.isNotEmpty) {
        await _refreshFromAmbulanceRow(profileId);
        return;
      }

      _isComplete = true;
      notifyListeners();
    } catch (e, st) {
      lastError = e.toString();
      notifyListeners();
      if (kDebugMode) {
        debugPrint('[ProfileCompletionService] Supabase error: $e\n$st');
      }
      if (kReleaseMode) rethrow;
    }
  }

  Future<void> refreshForAmbulance(String ambulanceId) async {
    if (ambulanceId.isEmpty) return;
    if (!SupabaseBootstrap.isReady) return;
    lastError = null;
    await _refreshFromAmbulanceRow(ambulanceId);
  }

  Future<void> _refreshFromAmbulanceRow(String ambulanceId) async {
    try {
      final amb = await SupabaseBootstrap.client
          .from('ambulances')
          .select('profile_completed')
          .eq('ambulance_id', ambulanceId)
          .maybeSingle();
      if (amb != null && amb['profile_completed'] is bool) {
        _isComplete = amb['profile_completed'] as bool;
      } else {
        _isComplete = true;
      }
      notifyListeners();
    } catch (e, st) {
      lastError = e.toString();
      notifyListeners();
      if (kDebugMode) {
        debugPrint('[ProfileCompletionService] ambulance Supabase: $e\n$st');
      }
      if (kReleaseMode) rethrow;
    }
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

  String? _rolePkColumn(UserType role) {
    return switch (role) {
      UserType.doctor => 'doctor_id',
      UserType.medicalStore => 'store_id',
      UserType.lab => 'lab_id',
      UserType.ambulance => 'ambulance_id',
      _ => null,
    };
  }

  Future<void> markComplete({
    required UserType role,
    required String uid,
    required String profileId,
  }) async {
    lastError = null;
    if (!SupabaseBootstrap.isReady) return;
    try {
      final client = SupabaseBootstrap.client;
      final now = DateTime.now().toUtc().toIso8601String();
      await client.from('users').update({
        'profile_completed': true,
        'updated_at': now,
      }).or('id.eq.$uid,firebase_uid.eq.$uid');

      final table = _roleTable(role);
      final pk = _rolePkColumn(role);
      if (table != null && pk != null && profileId.isNotEmpty) {
        await client.from(table).update({
          'profile_completed': true,
          'updated_at': now,
        }).eq(pk, profileId);
      }

      _isComplete = true;
      notifyListeners();
    } catch (e, st) {
      lastError = e.toString();
      notifyListeners();
      if (kDebugMode) {
        debugPrint('[ProfileCompletionService] markComplete: $e\n$st');
      }
      if (kReleaseMode) rethrow;
    }
  }

  Future<void> markAmbulanceComplete(String ambulanceId) async {
    if (ambulanceId.isEmpty || !SupabaseBootstrap.isReady) return;
    lastError = null;
    try {
      await SupabaseBootstrap.client.from('ambulances').update({
        'profile_completed': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('ambulance_id', ambulanceId);
      _isComplete = true;
      notifyListeners();
    } catch (e, st) {
      lastError = e.toString();
      notifyListeners();
      if (kDebugMode) {
        debugPrint('[ProfileCompletionService] markAmbulanceComplete: $e\n$st');
      }
      if (kReleaseMode) rethrow;
    }
  }

  void reset() {
    _isComplete = true;
    lastError = null;
    notifyListeners();
  }

  Future<void> evaluateAndMarkFromRoleDoc({
    required UserType role,
    required String uid,
    required String profileId,
  }) async {
    if (_isComplete || profileId.isEmpty || !SupabaseBootstrap.isReady) return;

    lastError = null;
    try {
      final client = SupabaseBootstrap.client;
      final table = _roleTable(role);
      final pk = _rolePkColumn(role);
      if (table == null || pk == null) return;

      final row =
          await client.from(table).select().eq(pk, profileId).maybeSingle();
      if (row == null) return;

      if (role == UserType.doctor &&
          (DemoAuthConfig.isDemoDoctorPhone(profileId) ||
              DemoAuthConfig.isDemoDoctorId(profileId))) {
        _isComplete = true;
        notifyListeners();
        return;
      }

      final complete = VerificationRequirementsConfig.isComplete(role, row);
      if (!complete) return;

      if (role.isAmbulance) {
        await markAmbulanceComplete(profileId);
      } else if (uid.isNotEmpty) {
        await markComplete(role: role, uid: uid, profileId: profileId);
      }
    } catch (e, st) {
      lastError = e.toString();
      notifyListeners();
      if (kDebugMode) debugPrint('ProfileCompletionService.evaluate: $e\n$st');
      if (kReleaseMode) rethrow;
    }
  }
}