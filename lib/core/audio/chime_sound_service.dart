import 'package:flutter/foundation.dart';
import 'chime_sound_stub.dart' if (dart.library.html) 'chime_sound_web.dart';

abstract final class ChimeSoundService {
  ChimeSoundService._();

  /// Plays a clean, satisfying LinkedIn-style 2-tone success chime sound.
  static void playAcceptChime() {
    try {
      playAcceptChimePlatform();
    } catch (e) {
      if (kDebugMode) debugPrint('[ChimeSoundService] playAcceptChime error: $e');
    }
  }
}
