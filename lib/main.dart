import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/firebase/firebase_bootstrap.dart';
import 'core/invite/pending_invite_store.dart';
import 'core/media/gallery_image_picker.dart';
import 'core/notifications/ambulance_push_background.dart';
import 'core/performance/app_scroll_behavior.dart';
import 'core/system/edge_to_edge_bootstrap.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'features/doctor/clinical/data/symptoms_database.dart';
import 'features/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Native splash is Android/iOS only (`web: false` in pubspec). Web uses the
  // HTML splash in index.html, which flutter-first-frame already dismisses.
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: WidgetsBinding.instance);
  }
  GalleryImagePicker.enableAndroidPhotoPicker();

  await EdgeToEdgeBootstrap.configure();

  PendingInviteStore.captureFromUri(Uri.base);

  // Essential startup only — parallelize to shorten splash dwell time.
  await Future.wait<void>([
    FirebaseBootstrap.initialize(),
    AppThemeController.instance.init(),
  ]);

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(ambulancePushBackgroundHandler);
  }
  // Non-critical: load after first frame / in background.
  unawaited(SymptomsDatabase.instance.ensureLoaded());

  if (!kIsWeb) {
    FlutterNativeSplash.remove();
  }
  runApp(const DoctorNectApp());
}

class DoctorNectApp extends StatelessWidget {
  const DoctorNectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'DoctorNect',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const AppScrollBehavior(),
          themeMode: AppThemeController.instance.themeMode,
          theme: AppTheme.light(AppColors.doctorBlue),
          darkTheme: AppTheme.dark(AppColors.doctorBlue),
          builder: (context, child) {
            final brightness = Theme.of(context).brightness;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: EdgeToEdgeBootstrap.overlayStyleFor(brightness),
              child: child ?? const SizedBox.shrink(),
            );
          },
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('hi'),
            Locale('bn'),
            Locale('te'),
            Locale('mr'),
            Locale('ta'),
            Locale('ur'),
            Locale('gu'),
            Locale('kn'),
            Locale('ml'),
            Locale('pa'),
          ],
          home: const SplashScreen(),
        );
      },
    );
  }
}
