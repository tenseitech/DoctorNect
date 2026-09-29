import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';
import '../firebase/firestore_paths.dart';
import 's3_storage_service.dart';
import 'storage_feature_flag.dart';
import '../data/local_avatar_store.dart';
import '../../features/patient/profile/data/patient_photo_local_store.dart';
import '../../features/doctor/profile/data/doctor_photo_local_store.dart';

class ProfilePhotoUploadResult {
  final String? photoUrl;
  final String? photoKey;
  final String photoStorage;
  final bool success;

  const ProfilePhotoUploadResult({
    this.photoUrl,
    this.photoKey,
    required this.photoStorage,
    required this.success,
  });
}

class ProfilePhotoUploader {
  ProfilePhotoUploader._();

  static final ProfilePhotoUploader instance = ProfilePhotoUploader._();

  @visibleForTesting
  FirebaseFirestore? firestoreOverride;
  FirebaseFirestore get _db => firestoreOverride ?? FirebaseFirestore.instance;

  @visibleForTesting
  S3StorageService? s3Override;
  S3StorageService get _s3 => s3Override ?? S3StorageService.instance;

  /// Uploads patient profile photo.
  /// When S3 is enabled:
  /// 1. Uploads bytes to S3 (purpose: 'patient_profile', parentId: patientId).
  /// 2. Updates Firestore patients/{patientId} and users/{patientId} docs.
  /// 3. Deletes old S3 object ONLY after new upload AND Firestore updates succeeded.
  /// When S3 is disabled:
  /// Runs legacy upload / base64 fallback.
  Future<ProfilePhotoUploadResult> uploadPatientPhoto({
    required String patientId,
    required Uint8List bytes,
    String? oldPhotoKey,
    bool? useS3Override,
  }) async {
    if (patientId.isEmpty || bytes.isEmpty) {
      return const ProfilePhotoUploadResult(
          photoStorage: 'none', success: false);
    }

    // Save locally
    await PatientPhotoLocalStore.save(patientId, bytes);

    final useS3 = useS3Override ?? StorageFeatureFlag.useS3Storage;

    if (useS3) {
      // 1. S3 Upload
      final uploadResult = await _s3.uploadBytes(
        purpose: 'patient_profile',
        parentId: patientId,
        fileName: 'profile.jpg',
        contentType: 'image/jpeg',
        bytes: bytes,
      );

      final newObjectKey = uploadResult.objectKey;
      if (newObjectKey.isEmpty) {
        throw StateError('S3 upload returned empty objectKey.');
      }

      // 2. Firestore updates
      if (FirebaseBootstrap.isReady || firestoreOverride != null) {
        await _db.collection(FirestorePaths.patients).doc(patientId).set({
          'hasLocalPhoto': true,
          'photoKey': newObjectKey,
          'photoStorage': 's3',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await _db.collection(FirestorePaths.users).doc(patientId).set({
          'photoKey': newObjectKey,
          'photoStorage': 's3',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 3. Delete old S3 object ONLY after both upload and Firestore update succeeded
      if (oldPhotoKey != null &&
          oldPhotoKey.trim().isNotEmpty &&
          oldPhotoKey.trim() != newObjectKey) {
        try {
          await _s3.deleteObject(oldPhotoKey.trim());
        } catch (e) {
          if (kDebugMode)
            debugPrint(
                '[ProfilePhotoUploader] failed to delete old S3 photo: $e');
        }
      }

      return ProfilePhotoUploadResult(
        photoKey: newObjectKey,
        photoStorage: 's3',
        success: true,
      );
    } else {
      // Legacy path
      String? remoteUrl;
      if (FirebaseBootstrap.isReady || firestoreOverride != null) {
        try {
          remoteUrl = await PatientPhotoLocalStore.uploadToFirebaseStorage(
              patientId, bytes);
        } catch (_) {}
      }

      final finalUrl =
          remoteUrl ?? 'data:image/jpeg;base64,${base64Encode(bytes)}';

      if (FirebaseBootstrap.isReady || firestoreOverride != null) {
        await _db.collection(FirestorePaths.patients).doc(patientId).set({
          'hasLocalPhoto': true,
          'photoStorage': remoteUrl != null ? 'firebase' : 'base64',
          'photoUrl': remoteUrl ?? finalUrl,
          'photoURL': remoteUrl ?? finalUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await _db.collection(FirestorePaths.users).doc(patientId).set({
          'photoUrl': remoteUrl ?? finalUrl,
          'photoURL': remoteUrl ?? finalUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null && remoteUrl != null) {
            await user.updatePhotoURL(remoteUrl);
          }
        } catch (_) {}
      }

      return ProfilePhotoUploadResult(
        photoUrl: finalUrl,
        photoStorage: remoteUrl != null ? 'firebase' : 'base64',
        success: true,
      );
    }
  }

  /// Uploads doctor profile photo.
  /// When S3 is enabled:
  /// 1. Uploads bytes to S3 (purpose: 'doctor_profile', parentId: doctorId).
  /// 2. Updates Firestore doctors/{doctorId} and users/{ownerUid or doctorId} docs.
  /// 3. Deletes old S3 object ONLY after new upload AND Firestore updates succeeded.
  /// When S3 is disabled:
  /// Runs legacy upload / base64 fallback.
  Future<ProfilePhotoUploadResult> uploadDoctorPhoto({
    required String doctorId,
    required Uint8List bytes,
    String? oldPhotoKey,
    String? ownerUid,
    bool? useS3Override,
  }) async {
    if (doctorId.isEmpty || bytes.isEmpty) {
      return const ProfilePhotoUploadResult(
          photoStorage: 'none', success: false);
    }

    // Save locally
    await DoctorPhotoLocalStore.save(doctorId, bytes);

    final useS3 = useS3Override ?? StorageFeatureFlag.useS3Storage;

    if (useS3) {
      // 1. S3 Upload
      final uploadResult = await _s3.uploadBytes(
        purpose: 'doctor_profile',
        parentId: doctorId,
        fileName: 'profile.jpg',
        contentType: 'image/jpeg',
        bytes: bytes,
      );

      final newObjectKey = uploadResult.objectKey;
      if (newObjectKey.isEmpty) {
        throw StateError('S3 upload returned empty objectKey.');
      }

      // 2. Firestore updates
      if (FirebaseBootstrap.isReady || firestoreOverride != null) {
        await _db.collection(FirestorePaths.doctors).doc(doctorId).set({
          'photoKey': newObjectKey,
          'photoStorage': 's3',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final targetUid = ownerUid ?? doctorId;
        await _db.collection(FirestorePaths.users).doc(targetUid).set({
          'photoKey': newObjectKey,
          'photoStorage': 's3',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 3. Delete old S3 object ONLY after both upload and Firestore update succeeded
      if (oldPhotoKey != null &&
          oldPhotoKey.trim().isNotEmpty &&
          oldPhotoKey.trim() != newObjectKey) {
        try {
          await _s3.deleteObject(oldPhotoKey.trim());
        } catch (e) {
          if (kDebugMode)
            debugPrint(
                '[ProfilePhotoUploader] failed to delete old S3 photo: $e');
        }
      }

      return ProfilePhotoUploadResult(
        photoKey: newObjectKey,
        photoStorage: 's3',
        success: true,
      );
    } else {
      // Legacy path
      final base64String = base64Encode(bytes);
      final dataUrl = 'data:image/jpeg;base64,$base64String';
      String? storageUrl;

      if (FirebaseBootstrap.isReady || firestoreOverride != null) {
        try {
          storageUrl = await LocalAvatarStore.uploadToFirebaseStorage(
            storagePath: 'doctor_profiles/$doctorId/profile.jpg',
            role: 'doctor',
            id: doctorId,
            bytes: bytes,
          );
        } catch (_) {}
      }

      final finalUrl = storageUrl ?? dataUrl;

      if (FirebaseBootstrap.isReady || firestoreOverride != null) {
        await _db.collection(FirestorePaths.doctors).doc(doctorId).set({
          'photoUrl': finalUrl,
          'photoURL': finalUrl,
          'photoStorage': storageUrl != null ? 'firebase' : 'base64',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final targetUid = ownerUid ?? doctorId;
        await _db.collection(FirestorePaths.users).doc(targetUid).set({
          'photoUrl': finalUrl,
          'photoURL': finalUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      return ProfilePhotoUploadResult(
        photoUrl: finalUrl,
        photoStorage: storageUrl != null ? 'firebase' : 'base64',
        success: true,
      );
    }
  }

  /// Removes patient profile photo.
  Future<void> removePatientPhoto({
    required String patientId,
    String? currentPhotoKey,
  }) async {
    await PatientPhotoLocalStore.clear(patientId);

    if (FirebaseBootstrap.isReady || firestoreOverride != null) {
      await _db.collection(FirestorePaths.patients).doc(patientId).update({
        'hasLocalPhoto': false,
        'photoStorage': null,
        'photoKey': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
        'photoURL': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _db.collection(FirestorePaths.users).doc(patientId).update({
        'photoKey': FieldValue.delete(),
        'photoStorage': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
        'photoURL': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (currentPhotoKey != null && currentPhotoKey.trim().isNotEmpty) {
      try {
        await _s3.deleteObject(currentPhotoKey.trim());
      } catch (_) {}
    }
  }

  /// Removes doctor profile photo.
  Future<void> removeDoctorPhoto({
    required String doctorId,
    String? currentPhotoKey,
    String? ownerUid,
  }) async {
    await DoctorPhotoLocalStore.clear(doctorId);

    if (FirebaseBootstrap.isReady || firestoreOverride != null) {
      await _db.collection(FirestorePaths.doctors).doc(doctorId).update({
        'photoKey': FieldValue.delete(),
        'photoStorage': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
        'photoURL': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final targetUid = ownerUid ?? doctorId;
      await _db.collection(FirestorePaths.users).doc(targetUid).update({
        'photoKey': FieldValue.delete(),
        'photoStorage': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
        'photoURL': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (currentPhotoKey != null && currentPhotoKey.trim().isNotEmpty) {
      try {
        await _s3.deleteObject(currentPhotoKey.trim());
      } catch (_) {}
    }
  }
}
