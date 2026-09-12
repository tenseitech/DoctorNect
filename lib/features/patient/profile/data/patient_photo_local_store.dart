import 'package:flutter/foundation.dart';
import '../../../../core/data/local_avatar_store.dart';

/// On-device patient profile photo until Firebase Storage is enabled.
abstract final class PatientPhotoLocalStore {
  static const maxFileBytes = LocalAvatarStore.maxFileBytes;

  static Uint8List? readCached(String patientId) =>
      LocalAvatarStore.readCached('patient', patientId);

  static Future<Uint8List?> load(String patientId) =>
      LocalAvatarStore.load('patient', patientId);

  static Future<bool> save(String patientId, Uint8List bytes) =>
      LocalAvatarStore.save('patient', patientId, bytes);

  static Future<void> clear(String patientId) =>
      LocalAvatarStore.clear('patient', patientId);

  /// Uploads in-memory bytes to Firebase Storage and returns the download URL.
  static Future<String?> uploadToFirebaseStorage(String patientId, [Uint8List? bytes]) =>
      LocalAvatarStore.uploadToFirebaseStorage(
        storagePath: 'patients/$patientId/profile_photo.jpg',
        role: 'patient',
        id: patientId,
        bytes: bytes,
      );
}
