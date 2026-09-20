import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Enables Android 15+ edge-to-edge and transparent system bar styling.
abstract final class EdgeToEdgeBootstrap {
  static Future<void> configure() async {
    if (kIsWeb || !Platform.isAndroid) return;

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// Icon contrast only — avoid [SystemUiOverlayStyle.statusBarColor] /
  /// [SystemUiOverlayStyle.systemNavigationBarColor], which call deprecated
  /// Window APIs on Android 15+ when targeting SDK 35.
  static SystemUiOverlayStyle overlayStyleFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }
}
