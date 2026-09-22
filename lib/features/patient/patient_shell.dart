import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/auth/role_session_guard.dart';
import '../../core/enums/user_type.dart';
import '../../core/data/shared_appointments_store.dart';
import 'records/data/patient_lab_booking_store.dart';
import '../../core/session/patient_session.dart';
import '../../core/firebase/firebase_auth_service.dart';
import '../../core/notifications/app_notification.dart';
import '../../core/notifications/app_notification_navigator.dart';
import '../../core/notifications/in_app_notification_service.dart';
import '../../core/notifications/patient_in_app_notification_sync.dart';
import '../../core/notifications/patient_notification_prefs_sync.dart';
import '../../core/notifications/patient_appointment_watcher.dart';
import '../../core/notifications/patient_lab_booking_watcher.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/session/app_session.dart';
import '../../core/widgets/resampled_network_image.dart';
import '../../core/notifications/patient_notification_scheduler.dart';
import '../../core/notifications/patient_push_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../ambulance/ambulance_booking_screen.dart';
import '../ambulance/models/ambulance_models.dart';
import 'lab/my_labs_screen.dart';
import 'profile/data/patient_photo_local_store.dart';
import 'profile/data/patient_profile_mock.dart';
import '../shared/screens/patient_profile_screen.dart';
import 'widgets/patient_app_shell.dart';
import 'home/patient_home_screen.dart';
import 'appointments/patient_appointments_screen.dart';
import 'profile/widgets/profile_completion_dialog.dart';

class PatientProfileTabAvatar extends StatefulWidget {
  const PatientProfileTabAvatar({
    super.key,
    required this.selected,
    required this.iconColor,
    required this.size,
    this.fallbackIcon,
  });

  final bool selected;
  final Color iconColor;
  final double size;
  final IconData? fallbackIcon;

  @override
  State<PatientProfileTabAvatar> createState() =>
      _PatientProfileTabAvatarState();
}

typedef _PatientProfileTabAvatar = PatientProfileTabAvatar;

class _PatientProfileTabAvatarState extends State<PatientProfileTabAvatar> {
  Uint8List? _localBytes;

  @override
  void initState() {
    super.initState();
    PatientProfileMock.listenable.addListener(_onProfileChanged);
    _loadLocalPhoto();
  }

  @override
  void dispose() {
    PatientProfileMock.listenable.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    _loadLocalPhoto();
    if (mounted) setState(() {});
  }

  String _effectivePatientId() {
    if (PatientSession.loggedInPatientId.isNotEmpty) {
      return PatientSession.loggedInPatientId;
    }
    if (FirebaseBootstrap.isReady) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.uid.isNotEmpty) {
          return user.uid;
        }
      } catch (_) {}
    }
    return AppSession.patientId;
  }

  void _loadLocalPhoto() {
    final patientId = _effectivePatientId();
    if (patientId.isEmpty) {
      if (_localBytes != null) {
        setState(() => _localBytes = null);
      }
      return;
    }
    final cached = PatientPhotoLocalStore.readCached(patientId);
    if (cached != null && cached.isNotEmpty) {
      _localBytes = cached;
    } else {
      _localBytes = null;
      PatientPhotoLocalStore.load(patientId).then((bytes) {
        if (mounted && bytes != null && bytes.isNotEmpty) {
          setState(() => _localBytes = bytes);
        }
      });
    }
  }

  String _getInitial() {
    final p = PatientProfileMock.profile;
    if (p.photoInitial != null && p.photoInitial!.trim().isNotEmpty) {
      return p.photoInitial!.trim()[0].toUpperCase();
    }
    if (p.name.trim().isNotEmpty) {
      return p.name.trim()[0].toUpperCase();
    }
    final sessionName = PatientSession.loggedInPatientName.trim();
    if (sessionName.isNotEmpty) {
      return sessionName[0].toUpperCase();
    }
    if (FirebaseBootstrap.isReady) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        final authName = user?.displayName?.trim();
        if (authName != null && authName.isNotEmpty) {
          return authName[0].toUpperCase();
        }
      } catch (_) {}
    }
    return 'P';
  }

  Widget _buildInitialFallback(
    BuildContext context,
    double size, {
    bool isLoading = false,
  }) {
    final initial = _getInitial();
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D9488), Color(0xFF0369A1)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.inter(
          fontSize: size * 0.46,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PatientProfileMock.listenable,
      builder: (context, _) {
        final patientId = _effectivePatientId();
        final bytes =
            _localBytes ?? PatientPhotoLocalStore.readCached(patientId);
        final profile = PatientProfileMock.profile;
        String? photoUrl = profile.photoUrl?.trim();
        if ((photoUrl == null || photoUrl.isEmpty) &&
            FirebaseBootstrap.isReady) {
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null &&
                user.photoURL != null &&
                user.photoURL!.trim().isNotEmpty) {
              photoUrl = user.photoURL!.trim();
            }
          } catch (_) {}
        }

        Widget avatarContent;
        if (bytes != null && bytes.isNotEmpty) {
          avatarContent = Image.memory(
            bytes,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _buildInitialFallback(context, widget.size),
          );
        } else if (photoUrl != null && photoUrl.isNotEmpty) {
          if (photoUrl.startsWith('data:image')) {
            Uint8List? dataUriBytes;
            try {
              final commaIndex = photoUrl.indexOf(',');
              if (commaIndex != -1) {
                dataUriBytes = base64Decode(photoUrl.substring(commaIndex + 1));
              }
            } catch (_) {}
            if (dataUriBytes != null && dataUriBytes.isNotEmpty) {
              avatarContent = Image.memory(
                dataUriBytes,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _buildInitialFallback(context, widget.size),
              );
            } else {
              avatarContent = _buildInitialFallback(context, widget.size);
            }
          } else {
            avatarContent = Image.network(
              photoUrl,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              cacheWidth:
                  ResampledNetworkImage.cacheDimension(widget.size, context),
              cacheHeight:
                  ResampledNetworkImage.cacheDimension(widget.size, context),
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  return child;
                }
                return _buildInitialFallback(context, widget.size,
                    isLoading: true);
              },
              errorBuilder: (_, __, ___) =>
                  _buildInitialFallback(context, widget.size),
            );
          }
        } else {
          avatarContent = _buildInitialFallback(context, widget.size);
        }

        return Container(
          width: widget.size,
          height: widget.size,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.selected
                  ? AppColors.patientTeal
                  : AppColors.borderOf(context).withValues(alpha: 0.4),
              width: widget.selected ? 2.0 : 1.0,
            ),
          ),
          child: ClipOval(
            child: avatarContent,
          ),
        );
      },
    );
  }
}

class PatientShell extends StatefulWidget {
  const PatientShell({super.key});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _index = 0;

  static final _tabs = [
    const PatientTabItem(
      outlinedIcon: Icons.home_outlined,
      filledIcon: Icons.home_rounded,
      label: 'Home',
    ),
    const PatientTabItem(
      outlinedIcon: Icons.event_outlined,
      filledIcon: Icons.event_rounded,
      label: 'Appointments',
      shortLabel: 'Visits',
    ),
    const PatientTabItem(
      outlinedIcon: Icons.science_outlined,
      filledIcon: Icons.science_rounded,
      label: 'My Labs',
      shortLabel: 'Labs',
    ),
    const PatientTabItem(
      outlinedIcon: TablerIcons.ambulance,
      filledIcon: TablerIcons.ambulance,
      label: 'Ambulance',
    ),
    PatientTabItem(
      outlinedIcon: Icons.person_outline_rounded,
      filledIcon: Icons.person_rounded,
      label: 'Profile',
      customIconBuilder: (context, selected, iconColor, size) =>
          _PatientProfileTabAvatar(
        selected: selected,
        iconColor: iconColor,
        size: size,
        fallbackIcon:
            selected ? Icons.person_rounded : Icons.person_outline_rounded,
      ),
    ),
  ];

  void _selectTab(int index) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (!mounted) return;
    setState(() => _index = index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleSessionGuard.verifyRole(context, UserType.patient);
      unawaited(_startPatientNotifications());
    });
  }

  Future<void> _startPatientNotifications() async {
    final patientId = PatientSession.loggedInPatientId;
    final uid = FirebaseAuthService.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await PatientInAppNotificationSync.start(uid);
    }
    if (patientId.isNotEmpty) {
      PatientNotificationPrefsSync.start(patientId);
    }
    PatientNotificationScheduler.instance.runStartupChecks();
    PatientNotificationScheduler.instance.start();
    PatientPushService.onAppointmentPushOpened = _handleAppointmentPushOpen;
    PatientPushService.onPrescriptionPushOpened = _handlePrescriptionPushOpen;
    await _refreshSessionData();
    if (patientId.isNotEmpty) {
      await PatientPushService.registerPatient(patientId);
      PatientLabBookingWatcher.start(patientId);
      PatientAppointmentWatcher.start(patientId);
    }
    _openFromPushIfNeeded();

    if (mounted) {
      ProfileCompletionDialog.showIfNeeded(context);
    }
  }

  Future<void> _refreshSessionData() async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return;
    await SharedAppointmentsStore.instance.refreshForPatient(patientId);
    await PatientLabBookingStore.instance
        .refreshForPatient(patientId, preferCache: true);
  }

  void _openFromPushIfNeeded() {
    final appointmentId = PatientPushService.pendingOpenAppointmentId;
    if (appointmentId != null && appointmentId.isNotEmpty) {
      PatientPushService.pendingOpenAppointmentId = null;
      _navigateFromPush(
        type: 'appointment_status_update',
        appointmentId: appointmentId,
      );
      return;
    }

    final prescriptionId = PatientPushService.pendingOpenPrescriptionId;
    if (prescriptionId != null && prescriptionId.isNotEmpty) {
      PatientPushService.pendingOpenPrescriptionId = null;
      _navigateFromPush(
        type: 'pharmacy_delivery_update',
        prescriptionId: prescriptionId,
      );
    }
  }

  void _handleAppointmentPushOpen(String appointmentId) {
    PatientPushService.pendingOpenAppointmentId = null;
    _navigateFromPush(
      type: 'appointment_status_update',
      appointmentId: appointmentId,
    );
  }

  void _handlePrescriptionPushOpen(String prescriptionId) {
    PatientPushService.pendingOpenPrescriptionId = null;
    _navigateFromPush(
      type: 'pharmacy_delivery_update',
      prescriptionId: prescriptionId,
    );
  }

  void _navigateFromPush({
    required String type,
    String? appointmentId,
    String? prescriptionId,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await AppNotificationNavigator.openFromPushData(
        context,
        data: {
          'type': type,
          if (appointmentId != null) 'appointmentId': appointmentId,
          if (prescriptionId != null) 'prescriptionId': prescriptionId,
        },
        audience: NotificationAudience.patient,
      );
    });
  }

  @override
  void dispose() {
    PatientInAppNotificationSync.stop();
    PatientNotificationPrefsSync.stop();
    PatientNotificationScheduler.instance.stop();
    PatientLabBookingWatcher.stop();
    PatientAppointmentWatcher.stop();
    PatientPushService.onAppointmentPushOpened = null;
    PatientPushService.onPrescriptionPushOpened = null;
    super.dispose();
  }

  List<Widget> _buildPages() => [
        PatientHomeScreen(onSelectTab: _selectTab),
        const PatientAppointmentsScreen(),
        const MyLabsScreen(embeddedInShell: true),
        const AmbulanceBookingScreen(
          bookedByRole: AmbulanceBookedByRole.patient,
          embeddedInShell: true,
        ),
        PatientProfileScreen(
          embeddedInShell: true,
          onOpenAppointments: () => _selectTab(1),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final patientTheme = isDark
        ? AppTheme.dark(AppColors.patientTeal)
        : AppTheme.light(AppColors.patientTeal);
    return Theme(
      data: patientTheme,
      child: ListenableBuilder(
        listenable: InAppNotificationService.instance,
        builder: (context, _) {
          final hasUnread =
              InAppNotificationService.instance.unreadPatientCount > 0;
          // Home tab (index 0) hosts the notification bell — flag it when
          // anything new (appointment, lab, etc.) has been received.
          final requestDots = [hasUnread, false, false, false, false];
          return PatientAppShell(
            selectedIndex: _index,
            onDestinationSelected: _selectTab,
            tabs: _tabs,
            requestDots: requestDots,
            child: IndexedStack(
              index: _index,
              children: _buildPages(),
            ),
          );
        },
      ),
    );
  }
}
