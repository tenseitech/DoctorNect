import '../../core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/profile_completion_service.dart';
import '../../core/auth/role_session_guard.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/ambulance_auth_helper.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/notifications/ambulance_push_service.dart';
import '../../core/session/ambulance_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/adaptive_app_shell.dart';
import '../../widgets/complete_profile_prompt.dart';
import '../welcome/welcome_screen.dart';
import 'data/ambulance_login_cache.dart';
import 'ambulance_driver_home_screen.dart';
import 'ambulance_profile_screen.dart';
import 'data/ambulance_store.dart';
import 'models/ambulance_models.dart';
import 'screens/ambulance_notifications_screen.dart';
import '../../core/theme/app_typography.dart';

class AmbulanceShell extends StatefulWidget {
  const AmbulanceShell({super.key, required this.ambulance});

  final RegisteredAmbulance ambulance;

  @override
  State<AmbulanceShell> createState() => _AmbulanceShellState();
}

class _AmbulanceShellState extends State<AmbulanceShell> {
  static const _accent = Color(0xFFDC2626);

  int _index = 0;
  final _requestsKey = GlobalKey<AmbulanceDriverHomeScreenState>();

  static const _tabs = [
    (icon: TablerIcons.ambulance, label: 'Requests'),
    (icon: TablerIcons.bell, label: 'Notifications'),
    (icon: TablerIcons.user, label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    AmbulanceStore.instance.registerAmbulance(widget.ambulance);
    unawaited(_initSession());
  }

  Future<void> _initSession() async {
    await AmbulanceSession.setAmbulance(
      id: widget.ambulance.id,
      serviceName: widget.ambulance.serviceName,
      driverName: widget.ambulance.driverName,
    );
    await ProfileCompletionService.instance.refreshForAmbulance(widget.ambulance.id);
    await _prepareAuth();
    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser?.isAnonymous != true) {
      return;
    }
    await RoleSessionGuard.verifyAmbulanceSession(
      context,
      ambulanceId: widget.ambulance.id,
    );
    await _refreshProfile();
  }

  @override
  void dispose() {
    unawaited(AmbulancePushService.unregisterDriver());
    super.dispose();
  }

  Future<void> _prepareAuth() async {
    final ok = await AmbulanceAuthHelper.ensureSignedIn();
    if (ok) {
      await FirestoreService.instance.ambulance.linkDriverAuth(widget.ambulance.id);
      await AmbulancePushService.registerDriver(widget.ambulance.id);
    }
  }

  Future<void> _refreshProfile() async {
    final fresh = await FirestoreService.instance.ambulance.fetchAmbulanceById(widget.ambulance.id);
    if (fresh != null) {
      AmbulanceStore.instance.updateRegisteredAmbulance(fresh);
    }
  }

  void _onTabSelected(int index) {
    setState(() => _index = index);
  }

  void _openRequestsTab() {
    setState(() => _index = 0);
    _requestsKey.currentState?.openPendingTab();
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Logout', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(
          'Are you sure you want to logout from ${widget.ambulance.serviceName}?',
          style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final navigator = Navigator.of(context);
              await AmbulancePushService.unregisterDriver();
              await AmbulanceLoginCache.clear();
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('last_login_ambulance_username');
              final sessionCleared = await AmbulanceSession.clear();
              if (FirebaseBootstrap.isReady) {
                await FirebaseAuth.instance.signOut();
              }
              if (!context.mounted) return;
              if (!sessionCleared) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Signed out, but session data may not have cleared fully. '
                      'If you still auto-login after refresh, clear site data for this browser.',
                      style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                    ),
                    duration: const Duration(seconds: 6),
                  ),
                );
              }
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (_) => false,
              );
            },
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ambulanceTheme = isDark
        ? AppTheme.dark(_accent)
        : AppTheme.light(_accent);

    return Theme(
      data: ambulanceTheme,
      child: ListenableBuilder(
        listenable: AmbulanceStore.instance,
        builder: (context, _) {
          final ambulanceId = AmbulanceSession.loggedInAmbulanceId;
          final ambulance = AmbulanceStore.instance.findAmbulance(ambulanceId) ?? widget.ambulance;
          final unread = AmbulanceStore.instance.unreadAlertCount(ambulanceId);
          final hasPendingRequests = AmbulanceStore.instance.bookings
              .any((b) => b.isPending && b.acceptedAmbulanceId == null);
          final isOnline = ambulance.available;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.local_hospital, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ambulance.serviceName,
                                style: GoogleFonts.inter(fontSize: AppTypography.headlineSmall, fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                children: [
                                  Icon(
                                    isOnline ? Icons.circle : Icons.circle_outlined,
                                    size: 8,
                                    color: isOnline ? const Color(0xFF16A34A) : AppColors.textSecondaryOf(context),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      '${ambulance.driverName} · ${isOnline ? 'Online' : 'Offline'}',
                                      style: GoogleFonts.inter(
                                        fontSize: AppTypography.labelMedium,
                                        color: AppColors.textSecondaryOf(context),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: AdaptiveAppShell(
                  selectedIndex: _index,
                  onDestinationSelected: _onTabSelected,
                  accentColor: _accent,
                  showMobileLogout: false,
                  requestDots: [hasPendingRequests, false, false],
                  destinations: [
                    NavigationDestination(icon: Icon(_tabs[0].icon), label: _tabs[0].label),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: unread > 0,
                        label: Text('$unread'),
                        child: Icon(_tabs[1].icon),
                      ),
                      label: _tabs[1].label,
                    ),
                    NavigationDestination(icon: Icon(_tabs[2].icon), label: _tabs[2].label),
                  ],
                  child: IndexedStack(
                    index: _index,
                    children: [
                      ProfileDataGate(
                        role: UserType.ambulance,
                        child: AmbulanceDriverHomeScreen(key: _requestsKey),
                      ),
                      ProfileDataGate(
                        role: UserType.ambulance,
                        child: AmbulanceNotificationsScreen(onOpenRequests: _openRequestsTab),
                      ),
                      AmbulanceProfileScreen(
                        ambulanceId: ambulance.id,
                        embedded: true,
                        onLogout: _logout,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
