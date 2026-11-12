import 'package:flutter/widgets.dart';

import '../notifications/app_toast.dart';
import 'ambulance_enabled.dart';

/// Central helpers for routing and messaging when [AmbulanceEnabled] is off in release.
abstract final class AmbulanceEntryPoints {
  static bool get _on => AmbulanceEnabled.isOn;

  /// Patient bottom nav: Ambulance tab index when enabled (0-based).
  static const int patientShellAmbulanceTabIndex = 3;

  /// Patient bottom nav: Profile tab index when Ambulance is enabled.
  static const int patientShellProfileTabWithAmbulance = 4;

  /// Patient bottom nav: Profile tab index when Ambulance is hidden.
  static const int patientShellProfileTabWithoutAmbulance = 3;

  /// Number of patient shell bottom-nav tabs.
  static int get patientShellTabCount => _on ? 5 : 4;

  /// Maps a **logical** tab index from the 5-tab layout (with Ambulance at 3) to the
  /// physical index in the current shell. When Ambulance is off, logical indices 4 (Profile)
  /// becomes physical 3; logical 3 (Ambulance) is invalid — returns null and optionally toasts.
  static int? mapLogicalPatientTabToPhysical(
    int logicalIndex, {
    BuildContext? context,
    bool showUnavailableToast = true,
  }) {
    if (_on) {
      if (logicalIndex < 0 || logicalIndex > 4) return null;
      return logicalIndex;
    }
    if (logicalIndex < 0 || logicalIndex > 4) return null;
    if (logicalIndex == patientShellAmbulanceTabIndex) {
      if (showUnavailableToast && context != null && context.mounted) {
        AppToast.info(context, 'Ambulance booking is not available in this build.');
      }
      return null;
    }
    if (logicalIndex == patientShellProfileTabWithAmbulance) {
      return patientShellProfileTabWithoutAmbulance;
    }
    return logicalIndex;
  }

  static String get patientShellUnavailableMessage =>
      'Ambulance booking is not available in this build.';
}
