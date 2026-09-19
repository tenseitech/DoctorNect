import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/profile_completion_service.dart';
import '../../core/auth/registration_credentials.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/ambulance_auth_helper.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/firebase/firebase_error_messages.dart';
import '../../core/firebase/firestore_service.dart';
import '../../core/notifications/app_toast.dart';
import '../../core/validators/form_validators.dart';
import '../auth/widgets/simple_role_registration_form.dart';
import 'ambulance_shell.dart';
import 'data/ambulance_pin.dart';
import 'models/ambulance_models.dart';
import '../../core/theme/app_typography.dart';

class AmbulanceRegistrationScreen extends StatelessWidget {
  const AmbulanceRegistrationScreen({super.key, this.preVerifiedMobile});

  final String? preVerifiedMobile;

  static const _accent = Color(0xFFDC2626);

  Future<void> _showCredentialsDialog(
    BuildContext context, {
    required String username,
    required String pin,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Save your login credentials'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use these to sign in to your ambulance dashboard:',
              style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium),
            ),
            const SizedBox(height: 16),
            Text('Username',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            SelectableText(username,
                style:
                    GoogleFonts.inter(fontSize: AppTypography.headlineSmall)),
            const SizedBox(height: 12),
            Text('PIN', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            SelectableText(pin,
                style:
                    GoogleFonts.inter(fontSize: AppTypography.headlineSmall)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('I have saved these'),
          ),
        ],
      ),
    );
  }

  Future<void> _register(
    BuildContext context, {
    required String name,
    required String qualification,
    required String mobile,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      AppToast.error(
          context, 'Firebase is not connected. Check internet and restart.');
      return;
    }

    final mobileDigits = FormValidators.mobileDigits(mobile) ?? '';
    final username = RegistrationCredentials.usernameForMobile(mobileDigits);
    final pin = RegistrationCredentials.generatePin();

    final signedIn = await AmbulanceAuthHelper.ensureSignedIn();
    if (!signedIn) {
      if (!context.mounted) return;
      AppToast.error(
          context, 'Could not start a secure session. Please try again.');
      return;
    }

    final taken = await FirestoreService.instance.ambulance
        .fetchAmbulanceByUsername(username, preferCache: false)
        .timeout(const Duration(seconds: 20));
    if (!context.mounted) return;
    if (taken != null) {
      AppToast.error(context, 'This mobile number is already registered.');
      return;
    }

    final id = 'amb-reg-${DateTime.now().millisecondsSinceEpoch}';
    final pinHash = await compute(_hashAmbulancePin, pin);

    final ambulance = RegisteredAmbulance(
      id: id,
      serviceName: '$name Ambulance',
      ownerName: name,
      driverName: name,
      phone: mobile,
      vehicleNumber: '',
      ambulanceType: AmbulanceType.bls,
      city: '',
      username: username,
      licenseNumber: '',
      pin: pinHash,
      available: false,
      createdAt: DateTime.now(),
    );

    try {
      final result =
          await FirestoreService.instance.ambulance.registerAmbulance(
        ambulance,
        extraFields: {
          'qualification': qualification,
          'profileCompleted': false,
        },
      ).timeout(const Duration(seconds: 30));

      if (result.id == null) {
        if (!context.mounted) return;
        AppToast.error(context, result.error ?? 'Registration failed');
        return;
      }

      await ProfileCompletionService.instance.refreshForAmbulance(id);
      if (!context.mounted) return;

      await _showCredentialsDialog(context, username: username, pin: pin);
      if (!context.mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => AmbulanceShell(
            ambulance: ambulance.copyWith(serviceName: '$name Ambulance'),
          ),
        ),
        (route) => false,
      );
    } on TimeoutException {
      if (!context.mounted) return;
      AppToast.error(context, 'Registration timed out. Check your connection.');
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(
        context,
        describeUserFacingError(e,
            fallback: 'Registration failed. Please try again.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SimpleRoleRegistrationForm(
      role: UserType.ambulance,
      accentColor: _accent,
      appBarTitle: 'Ambulance Registration',
      welcomeTitle: 'Join as Ambulance Service',
      subtitle:
          'Quick signup — add vehicle and service details in your profile next',
      icon: Icons.local_hospital_outlined,
      nameLabel: 'Owner / manager name *',
      preVerifiedMobile: preVerifiedMobile,
      onSubmit: ({required name, required qualification, required mobile}) =>
          _register(
        context,
        name: name,
        qualification: qualification,
        mobile: mobile,
      ),
    );
  }
}

String _hashAmbulancePin(String pin) => AmbulancePin.hash(pin);
