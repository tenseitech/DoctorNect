import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_bootstrap.dart';

/// Ambulance drivers use username/PIN — use a dedicated anonymous Firebase session.
abstract final class AmbulanceAuthHelper {
  static Future<bool> ensureSignedIn() async {
    if (!FirebaseBootstrap.isReady) {
      await FirebaseBootstrap.initialize();
    }
    if (!FirebaseBootstrap.isReady) return false;

    final auth = FirebaseAuth.instance;

    if (auth.currentUser?.isAnonymous == true) {
      return refreshCallableAuthToken();
    }

    // Ambulance Firestore rules require an anonymous driver session. If a patient/doctor
    // session is still active in this browser, sign out and start a fresh anon session.
    if (auth.currentUser != null && auth.currentUser!.isAnonymous == false) {
      try {
        await auth.signOut();
        await auth.authStateChanges().firstWhere((u) => u == null).timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('Ambulance auth: could not clear existing session: $e\n$st');
        }
        return false;
      }
    }

    try {
      final credential = await auth.signInAnonymously();
      final user = credential.user ?? auth.currentUser;
      if (user == null) {
        if (kDebugMode) {
          debugPrint('Ambulance auth: anonymous sign-in returned no user');
        }
        return false;
      }

      await auth.authStateChanges().firstWhere((u) => u?.isAnonymous == true).timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );

      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        if (kDebugMode) {
          debugPrint('Ambulance auth: anonymous sign-in returned empty ID token');
        }
        return false;
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'Ambulance anonymous sign-in failed. Enable Anonymous auth in Firebase Console: $e\n$st',
        );
      }
      return false;
    }
  }

  /// Refreshes the anonymous driver ID token so callables receive Authorization.
  static Future<bool> refreshCallableAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final token = await user.getIdToken(true);
      return token != null && token.isNotEmpty;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Ambulance auth: getIdToken failed: $e\n$st');
      }
      return false;
    }
  }
}
