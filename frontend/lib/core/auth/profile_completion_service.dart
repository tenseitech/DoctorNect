import '../config/doctor_patient_cutover_flag.dart';
import '../supabase/supabase_bootstrap.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'demo_auth_config.dart';
import 'verification_lifecycle.dart';
import '../enums/user_type.dart';
import '../firebase/firebase_bootstrap.dart';
import '../config/firestore_forbidden_guard.dart';
import '../firebase/firestore_paths.dart';
import '../firebase/firestore_read_helper.dart';

/// Tracks whether a non-patient user has completed their full profile.
///
/// Production path: **Supabase** (`users`, role tables). Firestore is used only
/// in debug when Supabase is not ready (tests / legacy).
class ProfileCompletionService extends ChangeNotifier {
  ProfileCompletionService._();

  static final ProfileCompletionService instance = ProfileCompletionService._();

  bool _isComplete = true;

  /// `true` for patients and legacy accounts missing the field.
  bool get isComplete => _isComplete;

  /// Last profile sync failure (Supabase). Cleared on success.
  String? lastError;

  /// When set in tests, Firestore reads/writes for the **legacy** path go through this
  /// callback instead of `FirebaseFirestore.instance` (e.g. fake_cloud_firestore).
  static FirebaseFirestore Function()? _debugFirestoreOverride;

  @visibleForTesting
  static FirebaseFirestore Function()? get debugFirestoreOverride =>
      _debugFirestoreOverride;

  @visibleForTesting
  static set debugFirestoreOverride(FirebaseFirestore Function()? value) {
    assert(() {
      if (value != null && (kReleaseMode || debugForceReleaseMode)) {
        throw AssertionError(
          'debugFirestoreOverride must not be set in release mode',
        );
      }
      return true;
    }());
    _debugFirestoreOverride = value;
  }

  /// Test-only: treat runtime as release for debug hook setter assertions.
  @visibleForTesting
  static bool debugForceReleaseMode = false;

  FirebaseFirestore _effectiveFirestore() {
    final o = _debugFirestoreOverride?.call();
    if (o != null) return o;
    FirestoreForbiddenGuard.assertNotForbidden('ProfileCompletionService');
    return FirebaseFirestore.instance;
  }

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

    if (DoctorPatientCutoverFlag.isEnabled &&
        SupabaseBootstrap.isReady &&
        uid.isNotEmpty) {
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

        if (role.isAmbulance &&
            profileId != null &&
            profileId.isNotEmpty) {
          final amb = await client
              .from('ambulances')
              .select('profile_completed')
              .eq('ambulance_id', profileId)
              .maybeSingle();
          if (amb != null && amb['profile_completed'] is bool) {
            _isComplete = amb['profile_completed'] as bool;
            notifyListeners();
            return;
          }
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
      return;
    }

    if (!kDebugMode || !FirebaseBootstrap.isReady || uid.isEmpty) {
      return;
    }

    try {
      final userSnap = await FirestoreReadHelper.getDocument(
        reference: _effectiveFirestore()
            .collection(FirestorePaths.users)
            .doc(uid),
        preferCache: false,
      );
      if (role == UserType.doctor &&
          (DemoAuthConfig.isDemoDoctorPhone(profileId) ||
              DemoAuthConfig.isDemoDoctorId(profileId))) {
        _isComplete = true;
        notifyListeners();
        return;
      }
      final userData = userSnap.data();
      if (userData != null) {
        final mobile =
            userData['mobile'] as String? ?? userData['phone'] as String?;
        if (role == UserType.doctor &&
            DemoAuthConfig.isDemoDoctorPhone(mobile)) {
          _isComplete = true;
          notifyListeners();
          return;
        }
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
    if (DoctorPatientCutoverFlag.isEnabled && SupabaseBootstrap.isReady) {
      lastError = null;
      try {
        final client = SupabaseBootstrap.client;
        final amb = await client
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
      return;
    }
    await _refreshFromAmbulanceDoc(ambulanceId);
  }

  Future<void> _refreshFromAmbulanceDoc(String ambulanceId) async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      final snap = await FirestoreReadHelper.getDocument(
        reference: _effectiveFirestore()
            .collection(FirestorePaths.ambulances)
            .doc(ambulanceId),
        preferCache: false,
      );
      final flag = snap.data()?['profileCompleted'];
      _isComplete = flag is bool ? flag : true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ProfileCompletionService ambulance refresh: $e');
      }
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
    if (DoctorPatientCutoverFlag.isEnabled && SupabaseBootstrap.isReady) {
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
          debugPrint('[ProfileCompletionService] Supabase markComplete: $e\n$st');
        }
        if (kReleaseMode) rethrow;
      }
      return;
    }

    if (!kDebugMode || !FirebaseBootstrap.isReady) return;

    final fs = _effectiveFirestore();
    final batch = fs.batch();
    final userRef = fs.collection(FirestorePaths.users).doc(uid);
    batch.set(
        userRef,
        {
          'profileCompleted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    final roleCollection = switch (role) {
      UserType.doctor => FirestorePaths.doctors,
      UserType.medicalStore => FirestorePaths.medicalStores,
      UserType.lab => FirestorePaths.labs,
      UserType.ambulance => FirestorePaths.ambulances,
      _ => null,
    };

    if (roleCollection != null && profileId.isNotEmpty) {
      batch.set(
        fs.collection(roleCollection).doc(profileId),
        {'profileCompleted': true, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }

    await batch.commit();
    _isComplete = true;
    notifyListeners();
  }

  Future<void> markAmbulanceComplete(String ambulanceId) async {
    if (ambulanceId.isEmpty) return;
    if (DoctorPatientCutoverFlag.isEnabled && SupabaseBootstrap.isReady) {
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
      return;
    }
    if (!FirebaseBootstrap.isReady) return;
    await _effectiveFirestore()
        .collection(FirestorePaths.ambulances)
        .doc(ambulanceId)
        .set({
      'profileCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _isComplete = true;
    notifyListeners();
  }

  void reset() {
    _isComplete = true;
    lastError = null;
    _debugFirestoreOverride = null;
    debugForceReleaseMode = false;
    notifyListeners();
  }

  Future<void> evaluateAndMarkFromRoleDoc({
    required UserType role,
    required String uid,
    required String profileId,
  }) async {
    if (_isComplete || profileId.isEmpty) return;

    if (DoctorPatientCutoverFlag.isEnabled && SupabaseBootstrap.isReady) {
      lastError = null;
      try {
        final client = SupabaseBootstrap.client;
        final table = _roleTable(role);
        final pk = _rolePkColumn(role);
        if (table == null || pk == null) return;

        final row = await client
            .from(table)
            .select()
            .eq(pk, profileId)
            .maybeSingle();
        if (row == null) return;

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
      return;
    }

    if (!kDebugMode || !FirebaseBootstrap.isReady) return;

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
        reference: _effectiveFirestore().collection(collection).doc(profileId),
        preferCache: false,
      );
      final data = snap.data();
      final complete = VerificationRequirementsConfig.isComplete(role, data);
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
