import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/enums/user_type.dart';
import '../../core/firebase/firebase_auth_service.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/session/ambulance_session.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/mobile_scaffold.dart';
import '../../widgets/medibond_logo.dart';
import '../ambulance/ambulance_shell_auto.dart';
import '../ambulance/ambulance_invite_setup_screen.dart';
import '../dashboard/dashboard_shell.dart';
import '../auth/unified_auth_intro_screen.dart';
import '../../core/invite/invite_deep_link_resolver.dart';
import '../../core/invite/pending_ambulance_invite_store.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const _authWait = Duration(milliseconds: 500);

  /// Resolves the appropriate initial screen (login, invite setup, or role dashboard).
  static Future<Widget> resolveInitialScreen({
    bool initializeFirebase = true,
  }) async {
    if (PendingAmbulanceInviteStore.hasPending) {
      if (initializeFirebase) {
        await FirebaseBootstrap.initialize();
      }
      return AmbulanceInviteSetupScreen(
        inviteId: PendingAmbulanceInviteStore.inviteId!,
        token: PendingAmbulanceInviteStore.token!,
      );
    }

    // Firebase is usually already ready from main(); this is a no-op then.
    if (initializeFirebase) {
      await FirebaseBootstrap.initialize();
    }

    final auth = FirebaseAuthService.instance;

    // Brief wait for persisted auth (esp. web); never block longer than 500ms.
    if (FirebaseBootstrap.isReady && auth.currentUser == null) {
      try {
        await auth.authStateChanges.first.timeout(_authWait);
      } on TimeoutException {
        // Proceed with whatever session state is available.
      }
    }

    // Session restore + ambulance check in parallel (independent).
    final results = await Future.wait<Object?>([
      if (FirebaseBootstrap.isReady && auth.currentUser != null)
        auth.restoreSession()
      else
        Future<UserType?>.value(null),
      AmbulanceSession.hasPersistedSession(),
    ]);

    final role = results[0] as UserType?;
    final ambulancePersisted = results[1] as bool;

    if (role != null) {
      return DashboardShell(userType: role);
    }

    // Persisted ambulance session requires PIN re-entry via [AmbulanceShellAuto].
    if (ambulancePersisted) {
      return const AmbulanceShellAuto();
    }

    final inviteLogin = InviteDeepLinkResolver.loginScreenFromPendingInvite();
    return inviteLogin ?? const UnifiedAuthIntroScreen();
  }

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_goNext());
  }

  Future<void> _goNext() async {
    final target = await SplashScreen.resolveInitialScreen();
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => target));
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return MobileScaffold(
      padding: EdgeInsets.zero,
      scrollable: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const DoctorNectLogo(size: 88),
          const SizedBox(height: 28),
          Text(
            'Your Health, Our Priority',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondaryOf(context),
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
