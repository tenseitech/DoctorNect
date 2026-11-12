import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';

/// Background FCM handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> ambulancePushBackgroundHandler(RemoteMessage message) async {
  await FirebaseBootstrap.initialize();
  if (kDebugMode) {
    debugPrint('Ambulance push (background): ${message.notification?.title}');
  }
}
