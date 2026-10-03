import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Background FCM handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> ambulancePushBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    debugPrint('Ambulance push (background): ${message.notification?.title}');
  }
}
