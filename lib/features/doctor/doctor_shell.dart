import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/auth/profile_completion_service.dart';
import '../../core/auth/role_session_guard.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firebase_auth_service.dart';
import '../../core/firebase/firestore_screen_sync.dart';
import '../../core/session/doctor_session.dart';

import '../../core/notifications/app_notification.dart';
import '../../core/notifications/app_notification_navigator.dart';
import '../../core/notifications/doctor_in_app_notification_sync.dart';
import '../../core/notifications/doctor_notification_scheduler.dart';
import '../../core/notifications/doctor_push_service.dart';
import '../../core/notifications/in_app_notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/adaptive_app_shell.dart';
import '../../widgets/complete_profile_prompt.dart';
import 'appointments/doctor_appointments_screen.dart';
import 'home/doctor_home_screen.dart';
import 'patients/doctor_patients_screen.dart';
import 'pharmacy/doctor_connected_stores_screen.dart';
import 'lab/doctor_connected_labs_screen.dart';
import 'profile/data/doctor_profile_store.dart';
import '../pharmacy/data/pharmacy_connection_store.dart';
import '../lab/data/lab_connection_store.dart';
import '../lab/data/lab_registry.dart';
import 'patients/data/doctor_patients_service.dart';

class DoctorShell extends StatefulWidget {
  const DoctorShell({super.key, this.verificationPending = false});

  final bool verificationPending;

  @override
  State<DoctorShell> createState() => _DoctorShellState();
}

class _DoctorShellState extends State<DoctorShell> {
  int _index = 0;
  int _appointmentsTab = 0;
  late final PageController _pageController =
      PageController(initialPage: _index);
  bool _isAnimatingToPage = false;
  final Set<int> _visitedTabs = {0};

  // Order: Home | Patients | Appointments (center) | Medical Store | Labs
  static final _destinations = [
    const NavigationDestination(
      icon: Icon(Icons.home_outlined, size: 22),
      selectedIcon: Icon(Icons.home_rounded, size: 22),
      label: 'Home',
    ),
    const NavigationDestination(
      icon: Icon(TablerIcons.users, size: 22),
      selectedIcon: Icon(TablerIcons.users, size: 22),
      label: 'Patients',
    ),
    const NavigationDestination(
      icon: Icon(TablerIcons.calendar, size: 22),
      selectedIcon: Icon(TablerIcons.calendar_filled, size: 22),
      label: 'Appointments',
    ),
    const NavigationDestination(
      icon: Icon(TablerIcons.pill, size: 22),
      selectedIcon: Icon(TablerIcons.pill_filled, size: 22),
      label: 'Medical Store',
    ),
    const NavigationDestination(
      icon: Icon(TablerIcons.flask, size: 22),
      selectedIcon: Icon(TablerIcons.flask_filled, size: 22),
      label: 'Labs',
    ),
  ];

  void _openAppointments(int tab) {
    setState(() {
      _visitedTabs.add(2);
      _appointmentsTab = tab.clamp(0, 3);
      _index = 2;
    });
    _syncFirestoreForTab(2);
    if (_pageController.hasClients) {
      _isAnimatingToPage = true;
      _pageController.jumpToPage(2);
      _isAnimatingToPage = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_onPageScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleSessionGuard.verifyRole(context, UserType.doctor);
      unawaited(_startDoctorNotifications());
      _attachConnectionListeners();
    });
  }

  void _attachConnectionListeners() {
    if (!ProfileCompletionService.instance.isComplete) return;
    if (widget.verificationPending) return;
    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isEmpty) return;
    FirestoreScreenSync.attachPendingConnections(
        role: UserType.doctor, profileId: doctorId);
    FirestoreScreenSync.attachLabPendingConnections(
        role: UserType.doctor, profileId: doctorId);
    FirestoreScreenSync.attachDoctorAppointments(doctorId);
  }

  List<bool> _requestDots(String doctorId) {
    final storePending =
        PharmacyConnectionStore.instance.pendingForDoctor(doctorId).isNotEmpty;
    final labPending =
        LabConnectionStore.instance.pendingForDoctor(doctorId).isNotEmpty;
    return [false, false, false, storePending, labPending];
  }

  void _onPageScroll() {
    if (_isAnimatingToPage) return;
    if (_pageController.hasClients) {
      final page = _pageController.page;
      if (page != null) {
        final nearestPage = page.round();
        if (_index != nearestPage) {
          setState(() {
            _visitedTabs.add(nearestPage);
            _index = nearestPage;
          });
        }
      }
    }
  }

  Future<void> _startDoctorNotifications() async {
    if (!ProfileCompletionService.instance.isComplete ||
        widget.verificationPending) {
      return;
    }
    // Defer all background work until after the first frame is drawn
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isNotEmpty) {
      await DoctorProfileStore.instance.ensureNotificationPrefsLoaded(doctorId);
    }
    InAppNotificationService.instance.seedDoctorWelcomeIfEmpty();
    DoctorNotificationScheduler.instance.runStartupChecks();
    DoctorNotificationScheduler.instance.start();
    DoctorPushService.onAppointmentPushOpened = _handleAppointmentPushOpen;
    final uid = FirebaseAuthService.instance.currentUser?.uid;
    if (doctorId.isNotEmpty) {
      await DoctorPushService.registerDoctor(doctorId);
    }
    if (uid != null && uid.isNotEmpty) {
      DoctorInAppNotificationSync.start(uid);
    }
    _openAppointmentFromPushIfNeeded();
  }

  void _openAppointmentFromPushIfNeeded() {
    final appointmentId = DoctorPushService.pendingOpenAppointmentId;
    if (appointmentId == null || appointmentId.isEmpty) return;
    DoctorPushService.pendingOpenAppointmentId = null;
    _navigateToAppointmentFromPush(appointmentId);
  }

  void _handleAppointmentPushOpen(String appointmentId) {
    DoctorPushService.pendingOpenAppointmentId = null;
    _navigateToAppointmentFromPush(appointmentId);
  }

  void _navigateToAppointmentFromPush(String appointmentId) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await AppNotificationNavigator.openFromPushData(
        context,
        data: {
          'type': 'appointment_new',
          'appointmentId': appointmentId,
        },
        audience: NotificationAudience.doctor,
      );
    });
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    FirestoreScreenSync.detachPendingConnections();
    FirestoreScreenSync.detachLabPendingConnections();
    FirestoreScreenSync.detachDoctorAppointments();
    DoctorInAppNotificationSync.stop();
    DoctorNotificationScheduler.instance.stop();
    DoctorPushService.onAppointmentPushOpened = null;
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (_index == index) return;
    setState(() {
      _visitedTabs.add(index);
      _index = index;
    });
    _syncFirestoreForTab(index);
    if (index == 1) {
      unawaited(DoctorPatientsService.refreshOnTabOpen());
    }
    if (_pageController.hasClients) {
      _isAnimatingToPage = true;
      _pageController
          .animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      )
          .then((_) {
        _isAnimatingToPage = false;
      });
    }
  }

  void _onPageChanged(int index) {
    if (_isAnimatingToPage) return;
    if (_index != index) {
      setState(() {
        _visitedTabs.add(index);
        _index = index;
      });
    }
    _syncFirestoreForTab(index);
    if (index == 1) {
      unawaited(DoctorPatientsService.refreshOnTabOpen());
    }
  }

  void _syncFirestoreForTab(int index) {
    if (!ProfileCompletionService.instance.isComplete ||
        widget.verificationPending) {
      return;
    }
    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isEmpty) return;

    _attachConnectionListeners();

    if (index == 3) {
      unawaited(PharmacyConnectionStore.instance.refreshActiveConnections(
        role: UserType.doctor,
        profileId: doctorId,
        preferCache: true,
      ));
    } else if (index == 4) {
      unawaited(LabConnectionStore.instance.refreshActiveConnections(
        role: UserType.doctor,
        profileId: doctorId,
        preferCache: true,
      ));
      unawaited(LabRegistry.refreshFromFirestore());
    }
  }

  Widget _lazyTab(int index) {
    if (!_visitedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    Widget tab;
    switch (index) {
      case 0:
        tab = KeepAliveWrapper(
          child: DoctorHomeScreen(
            key: const ValueKey('doctor_home'),
            onOpenAppointments: _openAppointments,
          ),
        );
      case 1:
        tab = const KeepAliveWrapper(
          child: DoctorPatientsScreen(key: ValueKey('doctor_patients')),
        );
      case 2:
        tab = KeepAliveWrapper(
          child: DoctorAppointmentsScreen(
            key: ValueKey<int>(_appointmentsTab),
            initialTabIndex: _appointmentsTab,
          ),
        );
      case 3:
        tab = const KeepAliveWrapper(
          child: DoctorConnectedStoresScreen(showAppBar: false),
        );
      case 4:
        tab = const KeepAliveWrapper(
          child: DoctorConnectedLabsScreen(showAppBar: false),
        );
      default:
        return const SizedBox.shrink();
    }
    return ProfileDataGate(
      role: UserType.doctor,
      verificationPending: widget.verificationPending,
      child: tab,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final doctorTheme = isDark
        ? AppTheme.dark(AppColors.doctorBlue)
        : AppTheme.light(AppColors.doctorBlue);
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          _onTabSelected(0);
        }
      },
      child: Theme(
        data: doctorTheme,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            PharmacyConnectionStore.instance,
            LabConnectionStore.instance,
          ]),
          builder: (context, _) {
            final doctorId = DoctorSession.loggedInDoctorId;
            return AdaptiveAppShell(
              selectedIndex: _index,
              onDestinationSelected: _onTabSelected,
              accentColor: AppColors.doctorBlue,
              filledActiveTabs: true,
              showMobileTopBar: false,
              destinations: _destinations,
              requestDots: _requestDots(doctorId),
              glassmorphic: true,
              child: PageView(
                physics: const NeverScrollableScrollPhysics(),
                controller: _pageController,
                onPageChanged: _onPageChanged,
                children: List.generate(_destinations.length, _lazyTab),
              ),
            );
          },
        ),
      ),
    );
  }
}

class KeepAliveWrapper extends StatefulWidget {
  const KeepAliveWrapper({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
