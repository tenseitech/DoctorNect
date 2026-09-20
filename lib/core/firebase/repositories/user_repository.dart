import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/user_type.dart';
import '../../validators/form_validators.dart';
import '../firestore_paths.dart';
import '../models/medibond_user_profile.dart';
import '../firestore_read_helper.dart';

class UserRepository {
  UserRepository._();

  static final UserRepository instance = UserRepository._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<DoctorNectUserProfile?> fetchProfile(String uid,
      {bool preferCache = true}) async {
    final snap = await FirestoreReadHelper.getDocument(
      reference: _db.collection(FirestorePaths.users).doc(uid),
      preferCache: preferCache,
    );
    if (!snap.exists || snap.data() == null) return null;
    return DoctorNectUserProfile.fromMap(uid, snap.data()!);
  }

  Future<void> createProfile({
    required User user,
    required UserType role,
    required String profileId,
    required String displayName,
    String? mobile,
    bool mobileVerified = false,
    Map<String, dynamic>? roleData,
  }) async {
    final userRef = _db.collection(FirestorePaths.users).doc(user.uid);
    final normalizedMobile =
        mobile == null ? null : FormValidators.mobileDigits(mobile);
    await userRef.set({
      'role': switch (role) {
        UserType.superAdmin => 'super_admin',
        UserType.doctor => 'doctor',
        UserType.medicalStore => 'medicalStore',
        UserType.patient => 'patient',
        UserType.lab => 'lab',
        UserType.ambulance => 'ambulance',
      },
      'profileId': profileId,
      'displayName': displayName,
      'email': _normalizeEmail(user.email?.isNotEmpty == true
          ? user.email
          : roleData?['email'] as String?),
      if (normalizedMobile != null) 'mobile': normalizedMobile,
      if (mobileVerified) ...{
        'mobileVerified': true,
        'mobileVerifiedAt': FieldValue.serverTimestamp(),
      },
      'verified': role == UserType.doctor ? false : true,
      'status': role == UserType.doctor ? 'pending_review' : 'approved',
      'profileCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (roleData != null) {
      final collection = switch (role) {
        UserType.superAdmin => FirestorePaths.users,
        UserType.doctor => FirestorePaths.doctors,
        UserType.medicalStore => FirestorePaths.medicalStores,
        UserType.patient => FirestorePaths.patients,
        UserType.lab => FirestorePaths.labs,
        UserType.ambulance => FirestorePaths.ambulances,
      };
      await _db.collection(collection).doc(profileId).set({
        ...roleData,
        'profileCompleted': roleData['profileCompleted'] ?? false,
      });
    }
  }

  /// Repairs auth accounts where Firebase Auth exists but users/{uid} was never saved.
  Future<DoctorNectUserProfile?> repairMissingProfile({
    required User user,
    required UserType expectedRole,
  }) async {
    final existing = await fetchProfile(user.uid, preferCache: false);
    if (existing != null) return existing;

    final collection = switch (expectedRole) {
      UserType.superAdmin => FirestorePaths.users,
      UserType.doctor => FirestorePaths.doctors,
      UserType.medicalStore => FirestorePaths.medicalStores,
      UserType.patient => FirestorePaths.patients,
      UserType.lab => FirestorePaths.labs,
      UserType.ambulance => FirestorePaths.ambulances,
    };

    final roleDoc = await _findRoleDocForUser(
      user: user,
      collection: collection,
    );
    if (roleDoc == null) return null;

    final data = roleDoc.data();
    final profileId = switch (expectedRole) {
      UserType.superAdmin => user.uid,
      UserType.doctor => data['doctorId'] as String? ?? roleDoc.id,
      UserType.medicalStore => data['storeId'] as String? ?? roleDoc.id,
      UserType.patient => data['patientId'] as String? ?? roleDoc.id,
      UserType.lab => data['labId'] as String? ?? roleDoc.id,
      UserType.ambulance => data['ambulanceId'] as String? ?? roleDoc.id,
    };
    final displayName = switch (expectedRole) {
      UserType.superAdmin => 'Super Admin',
      UserType.doctor => data['name'] as String? ?? 'Doctor',
      UserType.medicalStore => data['storeName'] as String? ?? 'Medical Store',
      UserType.patient => data['name'] as String? ?? 'Patient',
      UserType.lab =>
        data['labName'] as String? ?? data['name'] as String? ?? 'Lab',
      UserType.ambulance => data['serviceName'] as String? ??
          data['name'] as String? ??
          'Ambulance',
    };

    await _db.collection(FirestorePaths.users).doc(user.uid).set({
      'role': switch (expectedRole) {
        UserType.superAdmin => 'super_admin',
        UserType.doctor => 'doctor',
        UserType.medicalStore => 'medicalStore',
        UserType.patient => 'patient',
        UserType.lab => 'lab',
        UserType.ambulance => 'ambulance',
      },
      'profileId': profileId,
      'displayName': displayName,
      'email': _normalizeEmail(
        user.email?.trim().isNotEmpty == true
            ? user.email
            : (data['email'] as String?),
      ),
      if (data['mobile'] is String) 'mobile': data['mobile'],
      if (data['phone'] is String) 'mobile': data['phone'],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return fetchProfile(user.uid, preferCache: false);
  }

  /// Links a Google/Apple session to an existing account saved under another Auth uid.
  Future<DoctorNectUserProfile?> relinkOAuthProfileByEmail({
    required User user,
    required UserType expectedRole,
  }) async {
    final email = user.email?.trim();
    if (email == null || email.isEmpty) return null;

    final roleValue = switch (expectedRole) {
      UserType.superAdmin => 'super_admin',
      UserType.doctor => 'doctor',
      UserType.medicalStore => 'medicalStore',
      UserType.patient => 'patient',
      UserType.lab => 'lab',
      UserType.ambulance => 'ambulance',
    };

    final collection = switch (expectedRole) {
      UserType.superAdmin => FirestorePaths.users,
      UserType.doctor => FirestorePaths.doctors,
      UserType.medicalStore => FirestorePaths.medicalStores,
      UserType.patient => FirestorePaths.patients,
      UserType.lab => FirestorePaths.labs,
      UserType.ambulance => FirestorePaths.ambulances,
    };

    try {
      for (final candidate in _emailCandidates(email)) {
        final snap = await _db
            .collection(FirestorePaths.users)
            .where('role', isEqualTo: roleValue)
            .where('email', isEqualTo: candidate)
            .limit(1)
            .get(const GetOptions(source: Source.server));
        if (snap.docs.isEmpty) continue;

        final existingDoc = snap.docs.first;
        final data = existingDoc.data();
        if (!_emailsMatch(data['email'] as String?, email)) continue;

        final profileId = data['profileId'] as String? ?? '';
        if (profileId.isEmpty) continue;

        final displayName = data['displayName'] as String? ??
            user.displayName ??
            switch (expectedRole) {
              UserType.superAdmin => 'Super Admin',
              UserType.doctor => 'Doctor',
              UserType.medicalStore => 'Medical Store',
              UserType.patient => 'Patient',
              UserType.lab => 'Lab',
              UserType.ambulance => 'Ambulance',
            };

        final normalizedEmail = _normalizeEmail(email);
        final roleRef = _db.collection(collection).doc(profileId);
        try {
          await roleRef.update({
            'ownerUid': user.uid,
            'email': normalizedEmail,
          });
        } on FirebaseException {
          await roleRef.set(
            {
              'ownerUid': user.uid,
              'email': normalizedEmail,
            },
            SetOptions(merge: true),
          );
        }

        await _db.collection(FirestorePaths.users).doc(user.uid).set({
          'role': roleValue,
          'profileId': profileId,
          'displayName': displayName,
          'email': normalizedEmail,
          if (data['mobile'] is String) 'mobile': data['mobile'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return await fetchProfile(user.uid, preferCache: false);
      }
    } on FirebaseException {
      return null;
    }
    return null;
  }

  /// Automatically provisions a patient profile when a new user signs in with Google.
  Future<DoctorNectUserProfile?> createGooglePatientProfile({
    required User user,
  }) async {
    try {
      final patientId = 'p${DateTime.now().millisecondsSinceEpoch}';
      final rawName = user.displayName?.trim();
      final displayName =
          (rawName != null && rawName.isNotEmpty) ? rawName : 'Patient';
      final rawEmail = user.email?.trim() ?? '';
      final normalizedEmail = _normalizeEmail(rawEmail);
      final photoUrl = user.photoURL;

      final patientData = <String, dynamic>{
        'patientId': patientId,
        'ownerUid': user.uid,
        'name': displayName,
        if (normalizedEmail != null && normalizedEmail.isNotEmpty)
          'email': normalizedEmail,
        if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty)
          'mobile': user.phoneNumber,
        'verified': true,
        'status': 'approved',
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _db
          .collection(FirestorePaths.patients)
          .doc(patientId)
          .set(patientData);

      await _db.collection(FirestorePaths.users).doc(user.uid).set({
        'role': 'patient',
        'profileId': patientId,
        'displayName': displayName,
        'email': normalizedEmail,
        if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty)
          'mobile': user.phoneNumber,
        'verified': true,
        'status': 'approved',
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return await fetchProfile(user.uid, preferCache: false);
    } catch (_) {
      return null;
    }
  }

  /// Searches for a user profile by email address across user documents.
  Future<DoctorNectUserProfile?> findProfileByEmail(String email) async {
    final normalized = _normalizeEmail(email);
    if (normalized == null || normalized.isEmpty) return null;
    for (final candidate in _emailCandidates(normalized)) {
      try {
        final snap = await _db
            .collection(FirestorePaths.users)
            .where('email', isEqualTo: candidate)
            .limit(1)
            .get(const GetOptions(source: Source.server));
        if (snap.docs.isNotEmpty) {
          return await fetchProfile(snap.docs.first.id, preferCache: false);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findRoleDocForUser({
    required User user,
    required String collection,
  }) async {
    try {
      final byOwner = await _db
          .collection(collection)
          .where('ownerUid', isEqualTo: user.uid)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (byOwner.docs.isNotEmpty) {
        final doc = byOwner.docs.first;
        await _ensureRoleDocEmail(doc, user.email);
        return doc;
      }
    } on FirebaseException {
      return null;
    }

    if (collection == FirestorePaths.ambulances) {
      try {
        final byAuth = await _db
            .collection(collection)
            .where('authUid', isEqualTo: user.uid)
            .limit(1)
            .get(const GetOptions(source: Source.server));
        if (byAuth.docs.isNotEmpty) {
          return byAuth.docs.first;
        }
      } on FirebaseException {
        return null;
      }
    }

    return null;
  }

  Iterable<String> _emailCandidates(String email) sync* {
    final trimmed = email.trim();
    yield trimmed;
    yield trimmed.toLowerCase();
  }

  bool _emailsMatch(String? a, String? b) {
    if (a == null || b == null) return false;
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }

  String? _normalizeEmail(String? email) {
    if (email == null) return null;
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty || trimmed.endsWith('@patient.doctornect.com'))
      return null;
    return trimmed;
  }

  Future<bool> _activeUsersDocExists(String uid) async {
    final normalized = uid.trim();
    if (normalized.isEmpty) return false;
    try {
      final snap = await _db.collection(FirestorePaths.users).doc(normalized).get(
            const GetOptions(source: Source.server),
          );
      return snap.exists;
    } on FirebaseException {
      return false;
    }
  }

  String _accountUidFromRoleDoc(UserType role, Map<String, dynamic> data) {
    if (role == UserType.ambulance) {
      final authUid = data['authUid'] as String? ?? '';
      if (authUid.trim().isNotEmpty) return authUid.trim();
    }
    return (data['ownerUid'] as String? ?? '').trim();
  }

  Future<void> _ensureRoleDocEmail(
    QueryDocumentSnapshot<Map<String, dynamic>> roleDoc,
    String? email,
  ) async {
    final normalized = _normalizeEmail(email);
    if (normalized == null || normalized.isEmpty) return;
    final stored = roleDoc.data()['email'] as String?;
    if (_emailsMatch(stored, normalized)) return;
    try {
      await roleDoc.reference.update({'email': normalized});
    } on FirebaseException {
      // Non-fatal — profile repair can continue without email backfill.
    }
  }

  /// Finds account email for phone login (no OTP). Tries common stored formats.
  Future<String?> findEmailByMobile({
    required UserType role,
    required String mobile,
  }) async {
    final digits = FormValidators.mobileDigits(mobile);
    if (digits == null) return null;

    final roleValue = switch (role) {
      UserType.superAdmin => 'super_admin',
      UserType.doctor => 'doctor',
      UserType.medicalStore => 'medicalStore',
      UserType.patient => 'patient',
      UserType.lab => 'lab',
      UserType.ambulance => 'ambulance',
    };

    final candidates = <String>{
      digits,
      '+91$digits',
      '91$digits',
      '0$digits',
    };

    for (final candidate in candidates) {
      try {
        final snap = await _db
            .collection(FirestorePaths.users)
            .where('role', isEqualTo: roleValue)
            .where('mobile', isEqualTo: candidate)
            .limit(1)
            .get(const GetOptions(source: Source.server));

        if (snap.docs.isEmpty) continue;
        final email = snap.docs.first.data()['email'] as String?;
        if (email != null && email.trim().isNotEmpty) {
          return email.trim();
        }
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied' || e.code == 'unauthenticated')
          return null;
      } catch (_) {}
    }

    return null;
  }

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
          } else {
            return 'An account with email "$normEmail" is already registered.';
          }
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
            } else {
              return 'An account with mobile number "$mobile" is already registered.';
            }
          }
        }
      }

      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'unauthenticated')
        return null;
      return 'Could not validate duplicate account details (${e.code}). Check your connection and try again.';
    } catch (_) {
      return null;
    }
  }

  Future<String?> checkDoctorCouncilNumberExists({
    required String councilNumber,
    required String doctorId,
  }) async {
    try {
      final trimmed = councilNumber.trim();
      if (trimmed.isEmpty) return null;
      final snap = await _db
          .collection(FirestorePaths.doctors)
          .where('councilNumber', isEqualTo: trimmed)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (snap.docs.any((doc) => doc.id != doctorId)) {
        return 'This council registration number is already associated with another account.';
      }
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return null;
      return 'Could not validate council registration number. Check your connection and try again.';
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteAuthUserQuietly(User user) async {
    try {
      await user.delete();
    } catch (_) {}
  }

  Future<void> deletePendingAuthUser(User user) => _deleteAuthUserQuietly(user);

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

  Future<UserType?> _findRoleWithEmail(String email) async {
    final norm = _normalizeEmail(email);
    if (norm == null || norm.isEmpty) return null;
    final candidates = _emailCandidates(norm).toSet();
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      try {
        final userSnap = await _db
            .collection(FirestorePaths.users)
            .where('email', isEqualTo: candidate)
            .limit(1)
            .get(const GetOptions(source: Source.server));
        if (userSnap.docs.isNotEmpty) {
          final role =
              _parseRoleString(userSnap.docs.first.data()['role'] as String?);
          if (role != null) return role;
        }
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }
    return null;
  }

  Future<UserType?> findRoleWithMobile(String mobile) {
    final digits = FormValidators.registrationMobileDigits(mobile) ??
        FormValidators.mobileDigits(mobile) ??
        mobile.trim();
    return _findRoleWithMobile(digits);
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

  Future<DoctorNectUserProfile?> findProfileByMobile({
    required UserType role,
    required String mobile,
  }) async {
    final digits = FormValidators.registrationMobileDigits(mobile) ??
        FormValidators.mobileDigits(mobile) ??
        mobile.trim();
    if (digits.isEmpty) return null;

    final candidates = _buildMobileCandidates(mobile);
    const fields = ['mobile', 'phone', 'phoneNumber', 'mobileNumber'];
    final roleStr = switch (role) {
      UserType.superAdmin => 'super_admin',
      UserType.doctor => 'doctor',
      UserType.medicalStore => 'medicalStore',
      UserType.patient => 'patient',
      UserType.lab => 'lab',
      UserType.ambulance => 'ambulance',
    };

    // 1. Search users collection across all candidate formats & field names in parallel
    final userFutures = <Future<QuerySnapshot<Map<String, dynamic>>?>>[];
    for (final candidate in candidates) {
      for (final field in fields) {
        userFutures.add(
          _db
              .collection(FirestorePaths.users)
              .where('role', isEqualTo: roleStr)
              .where(field, isEqualTo: candidate)
              .limit(1)
              .get(const GetOptions(source: Source.server))
              .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s,
                  onError: (_) => null),
        );
      }
    }
    final userSnaps = await Future.wait(userFutures);
    for (final userSnap in userSnaps) {
      if (userSnap != null && userSnap.docs.isNotEmpty) {
        final doc = userSnap.docs.first;
        if (doc.data()['mobile'] != digits) {
          _db.collection(FirestorePaths.users).doc(doc.id).set(
            {'mobile': digits},
            SetOptions(merge: true),
          );
        }
        return fetchProfile(doc.id, preferCache: true);
      }
    }

    // 2. Fallback: Search role collection (patients, doctors, etc.) in parallel
    final collPath = switch (role) {
      UserType.superAdmin => FirestorePaths.users,
      UserType.doctor => FirestorePaths.doctors,
      UserType.medicalStore => FirestorePaths.medicalStores,
      UserType.patient => FirestorePaths.patients,
      UserType.lab => FirestorePaths.labs,
      UserType.ambulance => FirestorePaths.ambulances,
    };

    final roleFutures = <Future<QuerySnapshot<Map<String, dynamic>>?>>[];
    for (final candidate in candidates) {
      for (final field in fields) {
        roleFutures.add(
          _db
              .collection(collPath)
              .where(field, isEqualTo: candidate)
              .limit(1)
              .get(const GetOptions(source: Source.server))
              .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s,
                  onError: (_) => null),
        );
      }
    }
    final roleSnaps = await Future.wait(roleFutures);
    for (final snap in roleSnaps) {
      if (snap != null && snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        var accountUid = _accountUidFromRoleDoc(role, doc.data());
        if (accountUid.isEmpty || !await _activeUsersDocExists(accountUid)) {
          final profileId = doc.id.trim();
          if (profileId.isNotEmpty) {
            try {
              final userSnap = await _db
                  .collection(FirestorePaths.users)
                  .where('profileId', isEqualTo: profileId)
                  .limit(1)
                  .get(const GetOptions(source: Source.server));
              if (userSnap.docs.isNotEmpty) {
                accountUid = userSnap.docs.first.id;
              }
            } on FirebaseException {
              continue;
            }
          }
        }
        if (accountUid.isEmpty || !await _activeUsersDocExists(accountUid)) {
          continue;
        }
        return fetchProfile(accountUid, preferCache: true);
      }
    }

    return null;
  }

  Future<UserType?> _findRoleWithMobile(String digits) async {
    final candidates = _buildMobileCandidates(digits);
    const fields = ['mobile', 'phone', 'phoneNumber', 'mobileNumber'];

    // 1. Search users collection in parallel
    final userFutures = <Future<QuerySnapshot<Map<String, dynamic>>?>>[];
    for (final candidate in candidates) {
      for (final field in fields) {
        userFutures.add(
          _db
              .collection(FirestorePaths.users)
              .where(field, isEqualTo: candidate)
              .limit(1)
              .get(const GetOptions(source: Source.server))
              .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s,
                  onError: (_) => null),
        );
      }
    }
    final userSnaps = await Future.wait(userFutures);
    for (final userSnap in userSnaps) {
      if (userSnap != null && userSnap.docs.isNotEmpty) {
        final doc = userSnap.docs.first;
        final role = _parseRoleString(doc.data()['role'] as String?);
        if (role != null) {
          if (doc.data()['mobile'] != digits) {
            _db.collection(FirestorePaths.users).doc(doc.id).set(
              {'mobile': digits},
              SetOptions(merge: true),
            );
          }
          return role;
        }
      }
    }

    // 2. Fallback: Search role collections in parallel
    final roleCollections = <UserType, String>{
      UserType.patient: FirestorePaths.patients,
      UserType.doctor: FirestorePaths.doctors,
      UserType.medicalStore: FirestorePaths.medicalStores,
      UserType.lab: FirestorePaths.labs,
      UserType.ambulance: FirestorePaths.ambulances,
    };

    final roleFutures = <Future<
        ({UserType role, QuerySnapshot<Map<String, dynamic>> snap})?>>[];
    for (final entry in roleCollections.entries) {
      final role = entry.key;
      final collPath = entry.value;

      for (final candidate in candidates) {
        for (final field in fields) {
          roleFutures.add(
            _db
                .collection(collPath)
                .where(field, isEqualTo: candidate)
                .limit(1)
                .get(const GetOptions(source: Source.server))
                .then<
                    ({
                      UserType role,
                      QuerySnapshot<Map<String, dynamic>> snap
                    })?>(
                  (s) => s.docs.isNotEmpty ? (role: role, snap: s) : null,
                  onError: (_) => null,
                ),
          );
        }
      }
    }
    final roleResults = await Future.wait(roleFutures);
    for (final match in roleResults) {
      if (match != null && match.snap.docs.isNotEmpty) {
        final doc = match.snap.docs.first;
        final accountUid = _accountUidFromRoleDoc(match.role, doc.data());
        if (accountUid.isEmpty || !await _activeUsersDocExists(accountUid)) {
          continue;
        }
        return match.role;
      }
    }

    return null;
  }

  UserType? _parseRoleString(String? roleStr) {
    return switch (roleStr) {
      'super_admin' || 'superAdmin' => UserType.superAdmin,
      'doctor' => UserType.doctor,
      'patient' => UserType.patient,
      'medicalStore' => UserType.medicalStore,
      'lab' => UserType.lab,
      'ambulance' => UserType.ambulance,
      _ => null,
    };
  }

  String _roleLabel(UserType role) {
    return switch (role) {
      UserType.superAdmin => 'Super Admin',
      UserType.doctor => 'Doctor',
      UserType.patient => 'Patient',
      UserType.medicalStore => 'Pharmacy / Medical Store',
      UserType.lab => 'Diagnostic Lab',
      UserType.ambulance => 'Ambulance Service',
    };
  }
}
