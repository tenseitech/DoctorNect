import 'dart:async';

import 'package:flutter/material.dart';

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
import '../../core/notifications/patient_notification_scheduler.dart';
import '../../core/notifications/patient_push_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/digital_health_card_sheet.dart';
import '../../widgets/emergency_sos_sheet.dart';
import '../shared/screens/patient_profile_screen.dart';
import 'widgets/patient_app_shell.dart';
import 'home/patient_home_screen.dart';
import 'appointments/patient_appointments_screen.dart';
import 'profile/widgets/profile_completion_dialog.dart';

class PatientShell extends StatefulWidget {
  const PatientShell({super.key});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _index = 0;

  static const _tabs = [
    PatientTabItem(
      outlinedIcon: Icons.home_outlined,
      filledIcon: Icons.home_rounded,
      label: 'Home',
    ),
    PatientTabItem(
      outlinedIcon: Icons.event_outlined,
      filledIcon: Icons.event_rounded,
      label: 'Appointments',
      shortLabel: 'Visits',
    ),
    PatientTabItem(
      outlinedIcon: Icons.badge_outlined,
      filledIcon: Icons.badge_rounded,
      label: 'Digital Pass',
      shortLabel: 'Pass',
    ),
    PatientTabItem(
      outlinedIcon: Icons.emergency_outlined,
      filledIcon: Icons.emergency_rounded,
      label: 'SOS',
    ),
    PatientTabItem(
      outlinedIcon: Icons.person_outline_rounded,
      filledIcon: Icons.person_rounded,
      label: 'Account',
    ),
  ];

  void _selectTab(int index) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (!mounted) return;

    switch (index) {
      case 2:
        DigitalHealthCardSheet.show(context, userType: UserType.patient);
        return;
      case 3:
        EmergencySosSheet.show(context);
        return;
      case 4:
        unawaited(PatientProfileScreen.open(context));
        return;
      default:
        setState(() => _index = index);
    }
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
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
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
