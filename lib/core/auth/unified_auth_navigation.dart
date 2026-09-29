import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'demo_auth_config.dart';
import 'registration_credentials.dart';
import 'registration_otp_service.dart';
import 'verification_lifecycle.dart';
import '../enums/user_type.dart';
import '../firebase/firebase_auth_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../firebase/firestore_service.dart';
import '../session/ambulance_session.dart';
import '../session/doctor_session.dart';
import '../session/lab_session.dart';
import '../session/medical_store_session.dart';
import '../validators/form_validators.dart';
import '../../features/ambulance/data/ambulance_store.dart';
import '../../features/ambulance/models/ambulance_models.dart';
import '../../features/auth/patient_registration_screen.dart';
import '../../features/dashboard/dashboard_shell.dart';
import '../../features/doctor/models/doctor_models.dart';
import '../../features/doctor/profile/data/doctor_profile_store.dart';
import '../../features/lab/data/lab_registry.dart';
import '../../features/pharmacy/data/medical_store_registry.dart';

/// Post-OTP navigation for the unified mobile auth flow.
abstract final class UnifiedAuthNavigation {
  /// Routes after role selection for a new user:
  /// - Patient skips verification and enters the app / patient setup.
  /// - Doctor, Pharmacy, Diagnostic Lab, and Ambulance enter the app immediately
  ///   in `profile_incomplete` state with no blocking popup or mandatory form.
  static void openRegistrationForm(
    BuildContext context, {
    required UserType role,
    required String mobileDigits,
  }) {
    final mobile = FormValidators.formatFullPhone('+91', mobileDigits);

    if (role == UserType.patient) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              PatientRegistrationScreen(preVerifiedMobile: mobileDigits),
        ),
      );
      return;
    }

    _enterAppInProfileIncompleteState(
      role: role,
      mobileDigits: mobileDigits,
      mobile: mobile,
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => DashboardShell(userType: role)),
      (_) => false,
    );
  }

  static void _enterAppInProfileIncompleteState({
    required UserType role,
    required String mobileDigits,
    required String mobile,
  }) {
    final isDemoDoctor =
        role == UserType.doctor &&
        DemoAuthConfig.isDemoDoctorPhone(mobileDigits);
    final initialStage = isDemoDoctor
        ? VerificationStage.verified
        : VerificationStage.profileIncomplete;

    switch (role) {
      case UserType.doctor:
        final doctorId = 'd${DateTime.now().millisecondsSinceEpoch}';
        DoctorSession.setDoctor(id: doctorId, name: 'Doctor');
        DoctorProfileStore.instance.reset();
        DoctorProfileStore.instance.profile.mobile = mobile;
        DoctorProfileStore.instance.profile.verificationStatus = isDemoDoctor
            ? VerificationStatus.verified
            : VerificationStatus.pending;
        RoleVerificationController.instance.setRoleState(
          UserType.doctor,
          stage: initialStage,
        );
        if (FirebaseBootstrap.isReady) {
          final email = RegistrationCredentials.emailForMobile(mobileDigits);
          final password = RegistrationCredentials.generatePassword();
          unawaited(
            FirebaseAuthService.instance.registerProfile(
              role: UserType.doctor,
              email: email,
              password: password,
              profileId: doctorId,
              displayName: 'Doctor',
              mobile: mobile,
              otpVerificationSessionId:
                  RegistrationOtpService.verificationSessionId,
              roleData: {
                'doctorId': doctorId,
                'name': 'Doctor',
                'qualification': '',
                'mobile': mobile,
                'email': email,
                'verified': isDemoDoctor,
                'verificationStatus': initialStage.wireValue,
                'status': isDemoDoctor ? 'approved' : 'pending_review',
                'profileCompleted': isDemoDoctor,
              },
            ),
          );
        }
      case UserType.medicalStore:
        final storeId = 'ms${DateTime.now().millisecondsSinceEpoch}';
        final email = RegistrationCredentials.emailForMobile(mobileDigits);
        MedicalStoreRegistry.register(
          id: storeId,
          storeName: '',
          ownerName: '',
          address: '',
          drugLicenseNumber: '',
          phone: mobile,
          email: email,
          verified: false,
        );
        MedicalStoreSession.setStore(id: storeId, name: 'Pharmacy');
        RoleVerificationController.instance.setRoleState(
          UserType.medicalStore,
          stage: VerificationStage.profileIncomplete,
        );
        if (FirebaseBootstrap.isReady) {
          final password = RegistrationCredentials.generatePassword();
          unawaited(
            FirebaseAuthService.instance.registerProfile(
              role: UserType.medicalStore,
              email: email,
              password: password,
              profileId: storeId,
              displayName: 'Pharmacy',
              mobile: mobile,
              otpVerificationSessionId:
                  RegistrationOtpService.verificationSessionId,
              roleData: {
                'storeId': storeId,
                'storeName': '',
                'name': '',
                'ownerName': '',
                'phone': mobile,
                'email': email,
                'verified': false,
                'verificationStatus': 'profile_incomplete',
                'status': 'pending_review',
                'profileCompleted': false,
              },
            ),
          );
        }
      case UserType.lab:
        final labId = 'lab${DateTime.now().millisecondsSinceEpoch}';
        final email = RegistrationCredentials.emailForMobile(mobileDigits);
        LabRegistry.register(
          id: labId,
          labName: '',
          address: '',
          licenseNumber: '',
          phone: mobile,
          email: email,
          verified: false,
        );
        LabSession.setLab(id: labId, name: 'Diagnostic Lab');
        RoleVerificationController.instance.setRoleState(
          UserType.lab,
          stage: VerificationStage.profileIncomplete,
        );
        if (FirebaseBootstrap.isReady) {
          final password = RegistrationCredentials.generatePassword();
          unawaited(
            FirebaseAuthService.instance.registerProfile(
              role: UserType.lab,
              email: email,
              password: password,
              profileId: labId,
              displayName: 'Diagnostic Lab',
              mobile: mobile,
              otpVerificationSessionId:
                  RegistrationOtpService.verificationSessionId,
              roleData: {
                'labId': labId,
                'labName': '',
                'name': '',
                'phone': mobile,
                'email': email,
                'verified': false,
                'verificationStatus': 'profile_incomplete',
                'status': 'pending_review',
                'profileCompleted': false,
              },
            ),
          );
        }
      case UserType.ambulance:
        final ambId = 'amb-reg-${DateTime.now().millisecondsSinceEpoch}';
        final ambulance = RegisteredAmbulance(
          id: ambId,
          serviceName: '',
          ownerName: '',
          driverName: '',
          phone: mobile,
          vehicleNumber: '',
          ambulanceType: AmbulanceType.bls,
          city: '',
          licenseNumber: '',
          available: false,
          verified: false,
          createdAt: DateTime.now(),
        );
        AmbulanceStore.instance.registerAmbulance(ambulance);
        unawaited(
          AmbulanceSession.setAmbulance(
            id: ambId,
            serviceName: 'Ambulance Service',
            driverName: '',
          ),
        );
        RoleVerificationController.instance.setRoleState(
          UserType.ambulance,
          stage: VerificationStage.profileIncomplete,
        );
        if (FirebaseBootstrap.isReady) {
          unawaited(
            FirestoreService.instance.ambulance.registerAmbulance(
              ambulance,
              extraFields: {
                'profileCompleted': false,
                'verified': false,
                'verificationStatus': 'profile_incomplete',
                'status': 'pending_review',
              },
            ),
          );
        }
      default:
        break;
    }
  }

  /// Handles Firebase-auth login result (doctor / patient / pharmacy / lab).
  static Future<void> handleSignInResult(
    BuildContext context, {
    required UserType role,
    required AuthSignInResult result,
  }) async {
    if (result.cancelled) return;

    if (result.pendingReview) {
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => DashboardShell(userType: role)),
        (_) => false,
      );
      return;
    }

    if (result.canReactivateAccount && role == UserType.doctor) {
      await _offerReactivation(context, role, result.reactivateBefore);
      return;
    }

    if (!result.success) {
      if (result.message != null && result.message!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message!),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    TextInput.finishAutofillContext(shouldSave: true);
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => DashboardShell(userType: role)),
      (_) => false,
    );
  }

  static Future<void> _offerReactivation(
    BuildContext context,
    UserType role,
    DateTime? reactivateBefore,
  ) async {
    final deadline = reactivateBefore != null
        ? DateFormat('d MMM yyyy').format(reactivateBefore)
        : '30 days';

    final shouldReactivate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Account deactivated'),
        content: Text(
          'Your profile is hidden from patients. Reactivate before $deadline to restore access.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseAuthService.instance.signOut();
              if (ctx.mounted) Navigator.pop(ctx, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reactivate account'),
          ),
        ],
      ),
    );

    if (!context.mounted || shouldReactivate != true) return;

    final result = await FirebaseAuthService.instance.reactivateDoctorAccount();
    if (!context.mounted) return;
    if (result.success) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => DashboardShell(userType: role)),
        (_) => false,
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'Could not reactivate account'),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
