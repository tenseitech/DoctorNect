import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../firebase/app_data_service.dart';
import '../notifications/app_toast.dart';
import '../session/ambulance_session.dart';
import '../session/app_session.dart';
import '../theme/app_colors.dart';
import '../../features/welcome/welcome_screen.dart';

/// User-facing message for profile delete-account failures (all roles).
String userFacingDeleteAccountError(Object error) {
  if (error is FirebaseFunctionsException) {
    final msg = error.message?.trim();
    if (msg != null && msg.isNotEmpty) {
      return msg;
    }
    return 'Could not delete account. Please try again.';
  }
  return 'Failed to delete account. Please try again.';
}

/// Shared confirm → callable → session clear → welcome navigation.
Future<void> confirmAndDeleteAccountFromProfile(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Account'),
      content: const Text(
        'Are you sure you want to permanently delete your account and all associated data? This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await AppDataService.instance.user.deleteAccount(user: user);
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await AmbulanceSession.clear();
    AppSession.clear();
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppToast.info(context, userFacingDeleteAccountError(e));
  }
}