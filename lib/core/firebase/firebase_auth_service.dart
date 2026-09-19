import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:cloud_functions/cloud_functions.dart';

import '../auth/app_credential_store.dart';
import '../auth/auth_rate_limiter.dart';
import '../auth/last_login_store.dart';
import '../auth/registration_otp_service.dart';
import '../auth/session_expiry.dart';
import '../security/abuse_protection_service.dart';
import '../security/client_request_throttle.dart';
import '../validators/form_validators.dart';
import '../auth/profile_completion_service.dart';
import '../enums/user_type.dart';
import '../data/shared_appointments_store.dart';
import '../notifications/app_notification.dart';
import '../notifications/doctor_in_app_notification_sync.dart';
import '../notifications/patient_in_app_notification_sync.dart';
import '../notifications/patient_notification_prefs_sync.dart';
import '../notifications/in_app_notification_service.dart';
import '../notifications/patient_push_service.dart';
import '../notifications/doctor_push_service.dart';
import '../../features/doctor/profile/data/doctor_profile_store.dart';
import '../../features/patient/profile/data/patient_profile_mock.dart';
import '../session/app_session.dart';
import '../session/doctor_session.dart';
import '../session/lab_session.dart'; // FIXED: lab session wiring
import '../session/medical_store_session.dart';
import '../session/patient_session.dart';
import '../../features/patient/data/patient_mock_data.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import 'firebase_bootstrap.dart';
import 'firebase_error_messages.dart';
import 'firestore_data_prefetch.dart';
import 'firestore_screen_sync.dart';
import 'models/medibond_user_profile.dart';

// FIXED: lab verification gate at login
// FIXED: store verification gate at login
/// Incorrect current password during [FirebaseAuthService.updatePassword].
class WrongPasswordAuthException implements Exception {
  const WrongPasswordAuthException();
}

/// New password rejected as too weak during [FirebaseAuthService.updatePassword].
class WeakPasswordAuthException implements Exception {
  const WeakPasswordAuthException();
}

/// Account update failed (email, password, or configuration).
class AuthUpdateException implements Exception {
  AuthUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthSignInResult {
  const AuthSignInResult._({
    required this.success,
    this.role,
    this.message,
    this.needsRegistration = false,
    this.pendingReview = false,
    this.canReactivateAccount = false,
    this.cancelled = false,
    this.reactivateBefore,
  });

  final bool success;
  final UserType? role;
  final String? message;

  /// OAuth succeeded but no Firestore profile — complete registration while signed in.
  final bool needsRegistration;

  /// Doctor profile exists but awaits admin verification.
  final bool pendingReview;

  /// Doctor account is deactivated but still inside the reactivation window.
  final bool canReactivateAccount;
  final bool cancelled;
  final DateTime? reactivateBefore;

  factory AuthSignInResult.ok(UserType role) =>
      AuthSignInResult._(success: true, role: role);

  factory AuthSignInResult.fail(String message) =>
      AuthSignInResult._(success: false, message: message);

  factory AuthSignInResult.needsRegistration({String? message}) =>
      AuthSignInResult._(
        success: false,
        needsRegistration: true,
        message: message,
      );

  factory AuthSignInResult.pendingReview() =>
      const AuthSignInResult._(success: false, pendingReview: true);

  factory AuthSignInResult.deactivatedCanReactivate(
          {DateTime? reactivateBefore}) =>
      AuthSignInResult._(
        success: false,
        canReactivateAccount: true,
        reactivateBefore: reactivateBefore,
        message: 'Your account is deactivated.',
      );

  factory AuthSignInResult.cancelled() =>
      const AuthSignInResult._(success: false, cancelled: true);
}

class GoogleRegistrationProfile {
  const GoogleRegistrationProfile({
    required this.displayName,
    required this.email,
    this.phoneNumber,
  });

  final String displayName;
  final String email;
  final String? phoneNumber;
}

class FirebaseAuthService {
  FirebaseAuthService._();

  static final FirebaseAuthService instance = FirebaseAuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => currentUser != null;

  Future<AuthSignInResult> signInWithEmail({
    required UserType expectedRole,
    required String email,
    required String password,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return AuthSignInResult.fail(
        'Firebase is not available. Use Chrome, Android, or iOS to sign in.',
      );
    }

    final cleanEmail = email.trim();
    final rateLimitMsg = AuthRateLimiter.check('email_login', cleanEmail);
    if (rateLimitMsg != null) {
      return AuthSignInResult.fail(rateLimitMsg);
    }
    final serverLimit = await _assertServerLoginAllowed(cleanEmail);
    if (serverLimit != null) {
      return AuthSignInResult.fail(serverLimit);
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      final user = credential.user!;

      var profile = await FirestoreService.instance.user.fetchProfile(
        user.uid,
        preferCache: true,
      );
      profile ??= await FirestoreService.instance.user.fetchProfile(
        user.uid,
        preferCache: false,
      );
      profile ??= await FirestoreService.instance.user.repairMissingProfile(
        user: user,
        expectedRole: expectedRole,
      );
      if (profile == null) {
        await _auth.signOut();
        return AuthSignInResult.fail(
          'Account profile not found. Please register again or contact support.',
        );
      }
      if (profile.role != expectedRole) {
        await _auth.signOut();
        return AuthSignInResult.fail(
            'This account is not a ${_roleLabel(expectedRole)} account.');
      }
      final approvalBlock = await _roleApprovalBlock(profile).timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );
      if (approvalBlock != null) return approvalBlock;

      AuthRateLimiter.clear('email_login', cleanEmail);
      await _clearServerLoginFailures(cleanEmail);
      await _applyProfile(profile, deferPatientProfile: true);
      await SessionExpiry.markAuthenticated();
      await LastLoginStore.save(expectedRole, cleanEmail);
      return AuthSignInResult.ok(profile.role);
    } on FirebaseAuthException catch (e) {
      AuthRateLimiter.recordFailure('email_login', cleanEmail);
      await _recordServerLoginFailure(cleanEmail);
      return AuthSignInResult.fail(describeFirebaseAuthError(e));
    } on FirebaseException catch (e) {
      await _auth.signOut();
      return AuthSignInResult.fail(
        describeFirebaseError(
          e,
          fallback:
              'Could not load account data. Check your connection and try again.',
        ),
      );
    } catch (e) {
      await _auth.signOut();
      return AuthSignInResult.fail(
        describeUserFacingError(e, fallback: 'Login failed. Please try again.'),
      );
    }
  }

  Future<AuthSignInResult> signInWithMobileOtp({
    required UserType expectedRole,
    required String mobile,
    required String otpCode,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return AuthSignInResult.fail(
        'Firebase is not available. Use Chrome, Android, or iOS to sign in.',
      );
    }

    final digits = FormValidators.registrationMobileDigits(mobile) ??
        FormValidators.mobileDigits(mobile);
    if (digits == null || digits.isEmpty) {
      return AuthSignInResult.fail('Enter a valid 10-digit mobile number.');
    }

    final rateLimitMsg = AuthRateLimiter.check('otp_login', digits);
    if (rateLimitMsg != null) {
      return AuthSignInResult.fail(rateLimitMsg);
    }

    final error = await RegistrationOtpService.verify(
      digits,
      otpCode,
      role: expectedRole,
      otpType: 'login',
    );
    if (error != null) {
      AuthRateLimiter.recordFailure('otp_login', digits);
      return AuthSignInResult.fail(error);
    }

    final sessionId = RegistrationOtpService.verificationSessionId;
    if (sessionId == null ||
        sessionId.isEmpty ||
        RegistrationOtpService.isLocalVerificationSession(sessionId)) {
      AuthRateLimiter.recordFailure('otp_login', digits);
      return AuthSignInResult.fail(
        'OTP verification session expired. Please request a new OTP.',
      );
    }

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final result = await functions
          .httpsCallable('completeMobileOtpLogin')
          .call<Map<String, dynamic>>({
        'mobile': digits,
        'sessionId': sessionId,
        'role': _roleValue(expectedRole),
      });
      final data = Map<String, dynamic>.from(result.data);
      final customToken = data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        return AuthSignInResult.fail(
            'Could not establish a secure session. Please try again.');
      }

      final credential = await _auth.signInWithCustomToken(customToken);
      final user = credential.user;
      if (user == null) {
        return AuthSignInResult.fail(
            'Could not establish a secure session. Please try again.');
      }

      RegistrationOtpService.clearVerificationSession();

      var profile = await FirestoreService.instance.user
          .fetchProfile(user.uid, preferCache: false);
      profile ??= await FirestoreService.instance.user.findProfileByMobile(
        role: expectedRole,
        mobile: digits,
      );
      if (profile == null) {
        await _auth.signOut();
        return AuthSignInResult.fail(
            'Account profile not found for this mobile number.');
      }
      if (profile.role != expectedRole) {
        await _auth.signOut();
        return AuthSignInResult.fail(
          'This mobile number is registered under a ${_roleLabel(profile.role)} account.',
        );
      }

      final approvalBlock = await _roleApprovalBlock(profile).timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );
      if (approvalBlock != null) return approvalBlock;

      AuthRateLimiter.clear('otp_login', digits);
      await _applyProfile(profile, deferPatientProfile: true);
      await SessionExpiry.markAuthenticated();
      await LastLoginStore.save(
        expectedRole,
        profile.email.isNotEmpty ? profile.email : mobile,
      );
      return AuthSignInResult.ok(profile.role);
    } on FirebaseFunctionsException catch (e) {
      AuthRateLimiter.recordFailure('otp_login', digits);
      return AuthSignInResult.fail(
        e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'OTP login failed. Please try again.',
      );
    } on FirebaseAuthException catch (e) {
      AuthRateLimiter.recordFailure('otp_login', digits);
      return AuthSignInResult.fail(describeFirebaseAuthError(e));
    } catch (e) {
      AuthRateLimiter.recordFailure('otp_login', digits);
      await _auth.signOut();
      return AuthSignInResult.fail(
        describeUserFacingError(e,
            fallback: 'OTP login failed. Please try again.'),
      );
    }
  }

  Future<AuthSignInResult> registerProfile({
    required UserType role,
    required String email,
    required String password,
    required String profileId,
    required String displayName,
    String? mobile,
    String? otpVerificationSessionId,
    Map<String, dynamic>? roleData,
    Future<Map<String, dynamic>> Function(
      User user,
      Map<String, dynamic> roleData,
    )? prepareRoleDataAfterAuth,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return AuthSignInResult.fail(
          'Firebase is not available on this platform yet.');
    }

    final abuseBlock =
        await AbuseProtectionService.assertAccountCreationAllowed(
      email: email,
      mobile: mobile,
    );
    if (abuseBlock != null) {
      return AuthSignInResult.fail(abuseBlock);
    }
    final burstBlock = ClientRequestThrottle.denyMessage(
      'signup',
      max: 5,
      window: const Duration(hours: 1),
      message: 'Too many account creation attempts. Please try again later.',
    );
    if (burstBlock != null) {
      return AuthSignInResult.fail(burstBlock);
    }

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user!;
      var data = roleData == null
          ? null
          : (Map<String, dynamic>.from(roleData)..['ownerUid'] = user.uid);

      final validationError =
          await FirestoreService.instance.user.validateNewRegistration(
        role: role,
        email: email,
        mobile: mobile,
        profileId: profileId,
        roleData: data,
      );
      if (validationError != null) {
        await FirestoreService.instance.user.deletePendingAuthUser(user);
        await _auth.signOut();
        return AuthSignInResult.fail(validationError);
      }

      if (prepareRoleDataAfterAuth != null) {
        try {
          data =
              await prepareRoleDataAfterAuth(user, data ?? <String, dynamic>{});
          data['ownerUid'] = user.uid;
        } catch (e) {
          await FirestoreService.instance.user.deletePendingAuthUser(user);
          await _auth.signOut();
          return AuthSignInResult.fail(
            'Registration failed while uploading verification documents: $e',
          );
        }
      }

      try {
        await FirestoreService.instance.user.createProfile(
          user: user,
          role: role,
          profileId: profileId,
          displayName: displayName,
          mobile: mobile,
          mobileVerified: false,
          roleData: data,
        );
        final saved = await FirestoreService.instance.user
            .fetchProfile(user.uid, preferCache: false);
        if (saved == null) {
          await user.delete();
          return AuthSignInResult.fail(
            'Could not save your account profile. Check internet and try again.',
          );
        }

        final normalizedMobile =
            mobile == null ? '' : FormValidators.mobileDigits(mobile) ?? '';
        if (normalizedMobile.isNotEmpty) {
          final sessionId = otpVerificationSessionId ??
              RegistrationOtpService.verificationSessionId;
          if (sessionId == null || sessionId.isEmpty) {
            await user.delete();
            return AuthSignInResult.fail(
              'Mobile OTP verification is required before registration.',
            );
          }
          if (!RegistrationOtpService.isLocalVerificationSession(sessionId)) {
            final finalizeError =
                await RegistrationOtpService.finalizeRegistrationVerification(
                    sessionId);
            if (finalizeError != null) {
              await user.delete();
              return AuthSignInResult.fail(finalizeError);
            }
          }
        }
      } catch (_) {
        await user.delete();
        return AuthSignInResult.fail(
          'Registration failed while saving profile. Please try again.',
        );
      }

      final profile = DoctorNectUserProfile(
        uid: user.uid,
        role: role,
        profileId: profileId,
        displayName: displayName,
        email: email.trim(),
        mobile: mobile,
      );
      AppCredentialStore.registerForRole(
        role: role,
        email: email.trim(),
        id: profileId,
        displayName: displayName,
        mobile: mobile,
      );
      await _applyProfile(profile);
      await SessionExpiry.markAuthenticated();
      await LastLoginStore.save(role, email);
      return AuthSignInResult.ok(role);
    } on FirebaseAuthException catch (e) {
      return AuthSignInResult.fail(describeFirebaseAuthError(e));
    } on FirebaseException catch (e) {
      return AuthSignInResult.fail(
        describeFirebaseError(
          e,
          fallback:
              'Registration could not validate your account details. Please try again.',
        ),
      );
    } catch (e) {
      return AuthSignInResult.fail(
        describeUserFacingError(
          e,
          fallback: 'Registration failed. Please try again.',
        ),
      );
    }
  }

  static const String _googleWebClientId =
      '658118593597-vja8h427vrg37k6os3l9sp0dofs1590v.apps.googleusercontent.com';
  static const String _googleIosClientId =
      '658118593597-79iinf5gtfbt1ivlfatlk5g7epkorni9.apps.googleusercontent.com';

  static GoogleSignIn _getGoogleSignIn() {
    return GoogleSignIn(
      clientId: (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS))
          ? _googleIosClientId
          : null,
      serverClientId: _googleWebClientId,
      scopes: const ['email', 'profile'],
    );
  }

  Future<AuthSignInResult> signInWithGoogle({required UserType role}) async {
    if (!FirebaseBootstrap.isReady) {
      final ready = await FirebaseBootstrap.initialize();
      if (!ready) {
        return AuthSignInResult.fail(FirebaseBootstrap.lastInitError ??
            'Firebase is not available on this platform yet.');
      }
    }

    try {
      UserCredential userCredential;
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        try {
          userCredential = await _auth.signInWithPopup(googleProvider);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'popup-blocked' ||
              e.code == 'popup-closed-by-user' ||
              e.code == 'cancelled-popup-request') {
            return AuthSignInResult.fail(
                'Google sign-in popup was cancelled or blocked by the browser. Please allow popups and try again.');
          }
          rethrow;
        }
      } else {
        final GoogleSignIn googleSignIn = _getGoogleSignIn();
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          return AuthSignInResult.cancelled();
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        if (googleAuth.idToken == null && googleAuth.accessToken == null) {
          return AuthSignInResult.fail(
              'Could not obtain Google authentication token. Please verify Google Play Services and try again.');
        }

        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        userCredential = await _auth.signInWithCredential(credential);
      }

      final User? user = userCredential.user;
      if (user == null) {
        return AuthSignInResult.fail(
            'Could not retrieve user credentials from Google.');
      }

      DoctorNectUserProfile? profile = await FirestoreService.instance.user
          .fetchProfile(user.uid, preferCache: false);
      if (profile == null) {
        profile =
            await FirestoreService.instance.user.relinkOAuthProfileByEmail(
          user: user,
          expectedRole: role,
        );
        if (profile == null) {
          if (role == UserType.patient) {
            profile =
                await FirestoreService.instance.user.createGooglePatientProfile(
              user: user,
            );
          }
          if (profile == null) {
            await _auth.signOut();
            return AuthSignInResult.needsRegistration(
              message:
                  'No ${_roleLabel(role)} account found for ${user.email ?? "this Google account"}. Please complete registration.',
            );
          }
        }
      } else if (profile.role != role) {
        await _auth.signOut();
        return AuthSignInResult.fail(
          'An account with this Google email is already registered as a ${_roleLabel(profile.role)}.',
        );
      }

      await _applyProfile(profile);
      await SessionExpiry.markAuthenticated();
      await LastLoginStore.save(role, profile.email);
      return AuthSignInResult.ok(role);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return AuthSignInResult.fail('Sign-in cancelled.');
      }
      if (e.code == 'unauthorized-domain') {
        return AuthSignInResult.fail(
          'Domain not authorized. Please add this domain to Firebase Console -> Authentication -> Settings -> Authorized domains.',
        );
      }
      if (e.code == 'account-exists-with-different-credential') {
        return AuthSignInResult.fail(
          'An account already exists with this email using a different sign-in method. Please log in with your email and password.',
        );
      }
      return AuthSignInResult.fail(describeFirebaseAuthError(e));
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled' || e.code == 'popup_closed_by_user') {
        return AuthSignInResult.cancelled();
      }
      if (e.message != null &&
          (e.message!.contains('10') || e.message!.contains('12500'))) {
        return AuthSignInResult.fail(
          'Google Sign-In configuration error: Please verify that the Android SHA-1 fingerprint is registered in Firebase Console.',
        );
      }
      return AuthSignInResult.fail(
          'Google Sign-In failed (${e.code}): ${e.message}');
    } catch (e) {
      return AuthSignInResult.fail('Google Sign-In failed: $e');
    }
  }

  Future<GoogleRegistrationProfile?> fetchGoogleRegistrationProfile({
    required UserType role,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      final ready = await FirebaseBootstrap.initialize();
      if (!ready) {
        throw AuthUpdateException(
            'Firebase is not available on this platform yet.');
      }
    }

    String? email;
    String? displayName;
    String? phoneNumber;

    if (kIsWeb) {
      try {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        final cred = await _auth.signInWithPopup(googleProvider);
        email = cred.user?.email;
        displayName = cred.user?.displayName;
        phoneNumber = cred.user?.phoneNumber;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' ||
            e.code == 'cancelled-popup-request' ||
            e.code == 'popup-blocked') {
          return null;
        }
        if (e.code == 'unauthorized-domain') {
          throw AuthUpdateException(
            'Domain not authorized. Please add this domain to Firebase Console -> Authentication -> Settings -> Authorized domains.',
          );
        }
        throw AuthUpdateException(describeFirebaseAuthError(e));
      }
    } else {
      final googleSignIn = _getGoogleSignIn();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null;
      email = googleUser.email;
      displayName = googleUser.displayName;
    }

    if (email == null || email.isEmpty) return null;

    return GoogleRegistrationProfile(
      displayName: displayName ?? '',
      email: email,
      phoneNumber: phoneNumber,
    );
  }

  Future<UserType?> restoreSession() async {
    if (!FirebaseBootstrap.isReady) return null;
    await SessionExpiry.restore();
    if (SessionExpiry.isExpired) {
      await signOut();
      return null;
    }
    final user = currentUser;
    if (user == null) return null;
    final profile = await FirestoreService.instance.user
        .fetchProfile(user.uid, preferCache: true);
    if (profile == null) {
      await _auth.signOut();
      return null;
    }
    if (profile.role == UserType.superAdmin) {
      await _applyProfile(profile,
          awaitPrefetch: false, deferPatientProfile: true);
      return profile.role;
    }
    if (profile.role == UserType.doctor) {
      if (await FirestoreService.instance.doctorAccount.isDeactivated(
        profile.profileId,
        preferCache: true,
      )) {
        await _auth.signOut();
        return null;
      }

      await _applyProfile(profile,
          awaitPrefetch: false, deferPatientProfile: true);
      return profile.role;
    }

    final approved = await FirestoreService.instance.roleAccount.isVerified(
      profile.role,
      profile.profileId,
      preferCache: true,
    );
    if (!approved) {
      await _auth.signOut();
      return null;
    }

    await _applyProfile(profile,
        awaitPrefetch: false, deferPatientProfile: true);
    return profile.role;
  }

  Future<void> signOut() async {
    FirestoreScreenSync.stopAll();
    await PatientPushService.unregisterPatient();
    await DoctorPushService.unregisterDoctor();
    DoctorInAppNotificationSync.stop();
    DoctorPushService.dispose();
    PatientInAppNotificationSync.stop();
    PatientNotificationPrefsSync.stop();
    SharedAppointmentsStore.instance.clearForSignOut();
    PatientProfileMock.resetNotificationPrefsSession();
    DoctorProfileStore.resetNotificationPrefsSession();
    InAppNotificationService.instance.clearSessionState();
    AppSession.clear();
    await SessionExpiry.clear();
    if (FirebaseBootstrap.isReady) {
      await _auth.signOut();
    }
  }

  Future<void> updatePassword(
      String currentPassword, String newPassword) async {
    if (!FirebaseBootstrap.isReady) {
      throw AuthUpdateException('Firebase is not available on this platform.');
    }
    final user = currentUser;
    final email = user?.email?.trim();
    if (user == null || email == null || email.isEmpty) {
      throw AuthUpdateException(
          'No signed-in account with email/password login.');
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          throw const WrongPasswordAuthException();
        case 'weak-password':
          throw const WeakPasswordAuthException();
        default:
          throw AuthUpdateException(
            describeFirebaseAuthError(e,
                fallback: 'Could not update password.'),
          );
      }
    }
  }

  Future<void> updateEmail(String newEmail) async {
    throw AuthUpdateException('Email address changes are not allowed.');
  }

  Future<void> updateMobile(String newMobile) async {
    final parsed = FormValidators.parsePhone(newMobile);
    final err = FormValidators.phoneLocal(parsed.localNumber,
        dialCode: parsed.dialCode);
    if (err != null) {
      throw AuthUpdateException(err);
    }

    PatientProfileMock.profile.mobile = FormValidators.formatFullPhone(
      parsed.dialCode,
      parsed.localNumber,
    );
    await PatientProfileMock.persistCurrentProfile();
  }

  Future<void> _applyProfile(
    DoctorNectUserProfile profile, {
    bool awaitPrefetch = false,
    bool deferPatientProfile = false,
  }) async {
    AppSession.clear();
    var skipPrefetch = false;
    switch (profile.role) {
      case UserType.superAdmin:
        AppSession.setSuperAdmin(
          id: profile.profileId.isNotEmpty ? profile.profileId : profile.uid,
          name: profile.displayName.isNotEmpty
              ? profile.displayName
              : 'Super Admin',
          email: profile.email,
        );
      case UserType.doctor:
        DoctorSession.setDoctor(
            id: profile.profileId, name: profile.displayName);
        await ProfileCompletionService.instance.refreshForUser(
          role: UserType.doctor,
          uid: profile.uid,
          profileId: profile.profileId,
        );
        final doctorVerified =
            await FirestoreService.instance.doctorAccount.isVerified(
          profile.profileId,
        );
        skipPrefetch =
            !ProfileCompletionService.instance.isComplete || !doctorVerified;
        if (doctorVerified && ProfileCompletionService.instance.isComplete) {
          await InAppNotificationService.instance
              .warmUpReadState(NotificationAudience.doctor);
        }
      case UserType.patient:
        PatientSession.setPatient(
            id: profile.profileId, name: profile.displayName);
        await InAppNotificationService.instance
            .warmUpReadState(NotificationAudience.patient);
        if (deferPatientProfile) {
          unawaited(_loadPatientContext(profile));
        } else {
          await _loadPatientContext(profile);
        }
      case UserType.medicalStore:
        MedicalStoreSession.setStore(
            id: profile.profileId, name: profile.displayName);
        await ProfileCompletionService.instance.refreshForUser(
          role: UserType.medicalStore,
          uid: profile.uid,
          profileId: profile.profileId,
        );
        skipPrefetch = !ProfileCompletionService.instance.isComplete;
      case UserType.lab:
        LabSession.setLab(id: profile.profileId, name: profile.displayName);
        await ProfileCompletionService.instance.refreshForUser(
          role: UserType.lab,
          uid: profile.uid,
          profileId: profile.profileId,
        );
        skipPrefetch = !ProfileCompletionService.instance.isComplete;
      case UserType.ambulance:
        break;
    }
    if (skipPrefetch) return;
    if (awaitPrefetch) {
      await _prefetchSafely(profile);
    } else {
      unawaited(_prefetchSafely(profile));
    }
  }

  Future<void> _loadPatientContext(DoctorNectUserProfile profile) async {
    await PatientProfileMock.loadFromFirestore(profile.profileId);
    PatientMockData.patient = PatientContext(
      name: profile.displayName,
      city: PatientProfileMock.profileCity,
    );
  }

  Future<AuthSignInResult> reactivateDoctorAccount() async {
    if (!FirebaseBootstrap.isReady) {
      return AuthSignInResult.fail(
        'Firebase is not available. Use Chrome, Android, or iOS to sign in.',
      );
    }

    final user = currentUser;
    if (user == null) {
      return AuthSignInResult.fail('Not signed in. Please log in again.');
    }

    try {
      final profile = await FirestoreService.instance.user
          .fetchProfile(user.uid, preferCache: false);
      if (profile == null || profile.role != UserType.doctor) {
        await _auth.signOut();
        return AuthSignInResult.fail('Doctor profile not found.');
      }

      final status =
          await FirestoreService.instance.doctorAccount.fetchDeactivationStatus(
        profile.profileId,
      );
      if (!status.deactivated) {
        await _applyProfile(profile);
        return AuthSignInResult.ok(UserType.doctor);
      }
      if (!status.canReactivate) {
        await _auth.signOut();
        return AuthSignInResult.fail(
          'Reactivation period expired. Contact support@doctornect.com.',
        );
      }

      await FirestoreService.instance.doctorAccount.reactivate(
        doctorId: profile.profileId,
        ownerUid: user.uid,
      );
      await _applyProfile(profile);
      final email = user.email?.trim();
      if (email != null && email.isNotEmpty) {
        await LastLoginStore.save(UserType.doctor, email);
      }
      return AuthSignInResult.ok(UserType.doctor);
    } on FirebaseException catch (e) {
      return AuthSignInResult.fail(
        describeFirebaseError(
          e,
          fallback:
              'Could not reactivate account. Check internet and try again.',
        ),
      );
    } catch (e) {
      return AuthSignInResult.fail(
        describeUserFacingError(
          e,
          fallback: 'Could not reactivate account. Please try again.',
        ),
      );
    }
  }

  Future<AuthSignInResult> signInSuperAdmin({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || password.isEmpty) {
      return AuthSignInResult.fail('Invalid email or password.');
    }

    final rateLimitMsg = AuthRateLimiter.check('admin_login', cleanEmail);
    if (rateLimitMsg != null) {
      return AuthSignInResult.fail(rateLimitMsg);
    }
    final serverLimit = await _assertServerLoginAllowed(cleanEmail);
    if (serverLimit != null) {
      return AuthSignInResult.fail(serverLimit);
    }

    if (!FirebaseBootstrap.isReady) {
      return AuthSignInResult.fail(
        'Firebase is not available. Use Chrome, Android, or iOS to sign in.',
      );
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      final user = credential.user!;
      final verificationBlock = await _requireEmailVerified(user);
      if (verificationBlock != null) {
        await _auth.signOut();
        AuthRateLimiter.recordFailure('admin_login', cleanEmail);
        await _recordServerLoginFailure(cleanEmail);
        return AuthSignInResult.fail('Invalid email or password.');
      }

      final profile = await FirestoreService.instance.user.fetchProfile(
        user.uid,
        preferCache: false,
      );
      if (profile == null || profile.role != UserType.superAdmin) {
        await _auth.signOut();
        AuthRateLimiter.recordFailure('admin_login', cleanEmail);
        await _recordServerLoginFailure(cleanEmail);
        // Generic failure prevents disclosing that an admin panel exists
        return AuthSignInResult.fail('Invalid email or password.');
      }

      AuthRateLimiter.clear('admin_login', cleanEmail);
      await _clearServerLoginFailures(cleanEmail);
      await _applyProfile(profile);
      await SessionExpiry.markAuthenticated();
      await LastLoginStore.save(UserType.superAdmin, cleanEmail);
      return AuthSignInResult.ok(profile.role);
    } on FirebaseAuthException {
      AuthRateLimiter.recordFailure('admin_login', cleanEmail);
      await _recordServerLoginFailure(cleanEmail);
      return AuthSignInResult.fail('Invalid email or password.');
    } catch (_) {
      await _auth.signOut();
      AuthRateLimiter.recordFailure('admin_login', cleanEmail);
      await _recordServerLoginFailure(cleanEmail);
      return AuthSignInResult.fail('Invalid email or password.');
    }
  }

  /// Email verification disabled — emails are stored only, not verified via link/OTP.
  Future<AuthSignInResult?> _requireEmailVerified(User user) async {
    return null;
  }

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  Future<String?> _assertServerLoginAllowed(String email) async {
    if (!FirebaseBootstrap.isReady) return null;
    final localBlock = ClientRequestThrottle.denyMessage(
      'login_gate',
      max: 40,
      window: const Duration(minutes: 15),
      message: 'Too many login attempts. Please try again later.',
    );
    if (localBlock != null) return localBlock;
    try {
      await _functions.httpsCallable('assertLoginAllowed').call({
        'identifier': email.trim().toLowerCase(),
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return e.message?.trim().isNotEmpty == true
            ? e.message
            : 'Too many login attempts. Please try again later.';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _recordServerLoginFailure(String email) async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      await _functions.httpsCallable('recordFailedLogin').call({
        'identifier': email.trim().toLowerCase(),
      });
    } catch (_) {}
  }

  Future<void> _clearServerLoginFailures(String email) async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      await _functions.httpsCallable('clearFailedLogins').call({
        'identifier': email.trim().toLowerCase(),
      });
    } catch (_) {}
  }

  String _roleValue(UserType role) => switch (role) {
        UserType.superAdmin => 'super_admin',
        UserType.doctor => 'doctor',
        UserType.patient => 'patient',
        UserType.medicalStore => 'medicalStore',
        UserType.lab => 'lab',
        UserType.ambulance => 'ambulance',
      };

  Future<AuthSignInResult?> _roleApprovalBlock(
      DoctorNectUserProfile profile) async {
    if (profile.role != UserType.doctor) {
      return null; // Super admin, patients, pharmacies, labs, ambulances have instant direct login
    }

    final deactivation = await _doctorDeactivationResult(profile.profileId);
    if (deactivation != null) return deactivation;
    // Unverified doctors stay signed in; DoctorVerificationGate shows hold screen.
    return null;
  }

  Future<AuthSignInResult?> _doctorDeactivationResult(String doctorId) async {
    final status = await FirestoreService.instance.doctorAccount
        .fetchDeactivationStatus(doctorId);
    if (!status.deactivated) return null;
    if (status.canReactivate) {
      return AuthSignInResult.deactivatedCanReactivate(
        reactivateBefore: status.reactivateBefore,
      );
    }
    await _auth.signOut();
    return AuthSignInResult.fail(
      'Reactivation period expired. Contact support@doctornect.com.',
    );
  }

  Future<void> _prefetchSafely(DoctorNectUserProfile profile) async {
    try {
      await FirestoreDataPrefetch.prefetch(
          role: profile.role, profileId: profile.profileId);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Firestore prefetch after login failed: $e\n$st');
      }
    }
  }

  String _roleLabel(UserType role) => switch (role) {
        UserType.superAdmin => 'Super Admin',
        UserType.doctor => 'Doctor',
        UserType.patient => 'Patient',
        UserType.medicalStore => 'Medical Store',
        UserType.lab => 'Diagnostic Lab',
        UserType.ambulance => 'Ambulance',
      };
}
