import 'package:flutter/foundation.dart';
import '../../../../core/data/local_avatar_store.dart';

/// Persists a doctor\'s profile photo locally (on-device) keyed by doctorId.
abstract final class DoctorPhotoLocalStore {
  static Uint8List? readCached(String doctorId) =>
      LocalAvatarStore.readCached('doctor', doctorId);

  static Future<Uint8List?> load(String doctorId) =>
      LocalAvatarStore.load('doctor', doctorId);

  static Future<void> save(String doctorId, Uint8List bytes) async =>
      await LocalAvatarStore.save('doctor', doctorId, bytes);

  static Future<void> clear(String doctorId) =>
      LocalAvatarStore.clear('doctor', doctorId);
}
