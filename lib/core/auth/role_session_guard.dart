import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../enums/user_type.dart';
import '../firebase/firebase_auth_service.dart';
import '../session/ambulance_session.dart';
import '../../features/welcome/welcome_screen.dart';
import '../firebase/firestore_service.dart';

/// Safety validator to guarantee that the currently signed-in Firebase user's
/// Firestore profile matches the role of the dashboard/shell being rendered.
abstract final class RoleSessionGuard {
  static Future<bool> verifyRole(
      BuildContext context, UserType expectedRole) async {
    if (expectedRole == UserType.ambulance) {
      return verifyAmbulanceSession(
        context,
        ambulanceId: AmbulanceSession.loggedInAmbulanceId,
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return false;
    }

    try {
      final profile = await FirestoreService.instance.user.fetchProfile(
        user.uid,
        preferCache: true,
      );
      if (profile == null || profile.role != expectedRole) {
        if (context.mounted) {
          await _handleMismatch(context);
        }
        return false;
      }
      return true;
    } catch (_) {
      // Fail closed: transient errors must not grant access to the wrong shell.
      if (context.mounted) {
        await _handleMismatch(context);
      }
      return false;
    }
  }

  /// Ambulance drivers use anonymous Firebase Auth + username/PIN — not users/{uid}.
  static Future<bool> verifyAmbulanceSession(
    BuildContext context, {
    required String ambulanceId,
  }) async {
    if (ambulanceId.trim().isEmpty) {
      if (context.mounted) await _handleMismatch(context);
      return false;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) {
      if (context.mounted) await _handleMismatch(context);
      return false;
    }

    if (!AmbulanceSession.isLoggedIn ||
        AmbulanceSession.loggedInAmbulanceId != ambulanceId) {
      if (context.mounted) await _handleMismatch(context);
      return false;
    }

    return true;
  }

  static Future<void> _handleMismatch(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session mismatch detected, please log in again.'),
      ),
    );
    await FirebaseAuthService.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }
}
