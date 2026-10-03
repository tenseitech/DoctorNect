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
import 'core/supabase/supabase_auth_service.dart';
import 'core/supabase/supabase_bootstrap.dart';
import 'core/system/edge_to_edge_bootstrap.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'features/doctor/clinical/data/symptoms_database.dart';
import 'features/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Native splash is Android/iOS only (`web: false` in pubspec).
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: WidgetsBinding.instance);
  }
  GalleryImagePicker.enableAndroidPhotoPicker();

  await EdgeToEdgeBootstrap.configure();

  PendingInviteStore.captureFromUri(Uri.base);

  // Essential startup only — parallelize initialization.
  await Future.wait<void>([
    FirebaseBootstrap.initialize(),
    () async {
      try {
        await SupabaseBootstrap.initialize();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[main] SupabaseBootstrap initialization caught: $e');
        }
      }
    }(),
    AppThemeController.instance.init(),
  ]);

  // Wire up the auth-state listener now that Supabase is ready.
  // SupabaseAuthService._() calls _initAuthStateListener() but silently
  // no-ops when isReady is false — touching the singleton here guarantees
  // it runs after SupabaseBootstrap.initialize() has set isReady = true.
  if (SupabaseBootstrap.isReady) {
    SupabaseAuthService.instance; // ignore: unnecessary_statements
  }

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(ambulancePushBackgroundHandler);
  }
  // Non-critical: load after first frame / in background.
  unawaited(SymptomsDatabase.instance.ensureLoaded());

  // On web, resolve the initial destination screen directly so no splash screen is shown.
  final Widget? webInitialScreen = kIsWeb
      ? await SplashScreen.resolveInitialScreen(initializeFirebase: false)
      : null;

  if (!kIsWeb) {
    FlutterNativeSplash.remove();
  }
  runApp(DoctorNectApp(initialScreen: webInitialScreen));
}

class DoctorNectApp extends StatelessWidget {
  const DoctorNectApp({super.key, this.initialScreen});

  final Widget? initialScreen;

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
            final mediaQuery = MediaQuery.of(context);
            final clampedMediaQuery = mediaQuery.copyWith(
              textScaler: mediaQuery.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.3,
              ),
            );
            final brightness = Theme.of(context).brightness;
            return MediaQuery(
              data: clampedMediaQuery,
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: EdgeToEdgeBootstrap.overlayStyleFor(brightness),
                child: child ?? const SizedBox.shrink(),
              ),
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
          home: initialScreen ?? const SplashScreen(),
        );
      },
    );
  }
}
