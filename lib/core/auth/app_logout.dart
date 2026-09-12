import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../firebase/firebase_auth_service.dart';
import '../session/ambulance_session.dart';
import '../session/app_session.dart';
import '../theme/app_colors.dart';
import '../../features/welcome/welcome_screen.dart';

/// Sign out back to role selection (Welcome).
abstract final class AppLogout {
  static Future<void> confirmAndSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: Text(
              'Log out',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await signOut(context);
    }
  }

  static Future<void> signOut(BuildContext context) async {
    await AmbulanceSession.clear();
    AppSession.clear();
    await FirebaseAuthService.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }
}
