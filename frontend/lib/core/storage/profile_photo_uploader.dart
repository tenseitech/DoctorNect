import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../firebase/firebase_bootstrap.dart';
import '../supabase/supabase_bootstrap.dart';
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
  static Future<void> Function({
    required String patientId,
    required String newObjectKey,
  })? debugPersistPatient;

  @visibleForTesting
  static Future<void> Function({
    required String doctorId,
    required String? ownerUid,
    required String newObjectKey,
  })? debugPersistDoctor;

  @visibleForTesting
  S3StorageService? s3Override;
  S3StorageService get _s3 => s3Override ?? S3StorageService.instance;

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

    await PatientPhotoLocalStore.save(patientId, bytes);

    final useS3 = useS3Override ?? StorageFeatureFlag.useS3Storage;

    if (useS3) {
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

      if (debugPersistPatient != null) {
        await debugPersistPatient!(
          patientId: patientId,
          newObjectKey: newObjectKey,
        );
      } else {
        await _persistPatientPhotoMetadata(
          patientId: patientId,
          newObjectKey: newObjectKey,
        );
      }

      if (oldPhotoKey != null &&
          oldPhotoKey.trim().isNotEmpty &&
          oldPhotoKey.trim() != newObjectKey) {
        try {
          await _s3.deleteObject(oldPhotoKey.trim());
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                '[ProfilePhotoUploader] failed to delete old S3 photo: $e');
          }
        }
      }

      return ProfilePhotoUploadResult(
        photoKey: newObjectKey,
        photoStorage: 's3',
        success: true,
      );
    }

    String? remoteUrl;
    if (FirebaseBootstrap.isReady) {
      try {
        remoteUrl = await PatientPhotoLocalStore.uploadToFirebaseStorage(
            patientId, bytes);
      } catch (_) {}
    }

    final finalUrl =
        remoteUrl ?? 'data:image/jpeg;base64,${base64Encode(bytes)}';

    return ProfilePhotoUploadResult(
      photoUrl: finalUrl,
      photoStorage: remoteUrl != null ? 'firebase' : 'base64',
      success: true,
    );
  }

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

    await DoctorPhotoLocalStore.save(doctorId, bytes);

    final useS3 = useS3Override ?? StorageFeatureFlag.useS3Storage;

    if (useS3) {
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

      if (debugPersistDoctor != null) {
        await debugPersistDoctor!(
          doctorId: doctorId,
          ownerUid: ownerUid,
          newObjectKey: newObjectKey,
        );
      } else {
        await _persistDoctorPhotoMetadata(
          doctorId: doctorId,
          ownerUid: ownerUid,
          newObjectKey: newObjectKey,
        );
      }

      if (oldPhotoKey != null &&
          oldPhotoKey.trim().isNotEmpty &&
          oldPhotoKey.trim() != newObjectKey) {
        try {
          await _s3.deleteObject(oldPhotoKey.trim());
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                '[ProfilePhotoUploader] failed to delete old S3 photo: $e');
          }
        }
      }

      return ProfilePhotoUploadResult(
        photoKey: newObjectKey,
        photoStorage: 's3',
        success: true,
      );
    }

    final base64String = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$base64String';
    String? storageUrl;

    if (FirebaseBootstrap.isReady) {
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

    return ProfilePhotoUploadResult(
      photoUrl: finalUrl,
      photoStorage: storageUrl != null ? 'firebase' : 'base64',
      success: true,
    );
  }

  Future<void> removePatientPhoto({
    required String patientId,
    String? currentPhotoKey,
  }) async {
    await PatientPhotoLocalStore.clear(patientId);

    if (SupabaseBootstrap.isReady) {
      try {
        await SupabaseBootstrap.client.from('patients').update({
          'photo_key': null,
          'photo_storage': null,
          'photo_s3_key': null,
          'photo_url': null,
          'photo_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('patient_id', patientId);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ProfilePhotoUploader] Supabase patient photo clear: $e');
        }
      }
    }

    if (currentPhotoKey != null && currentPhotoKey.trim().isNotEmpty) {
      try {
        await _s3.deleteObject(currentPhotoKey.trim());
      } catch (_) {}
    }
  }

  Future<void> removeDoctorPhoto({
    required String doctorId,
    String? currentPhotoKey,
    String? ownerUid,
  }) async {
    await DoctorPhotoLocalStore.clear(doctorId);

    if (SupabaseBootstrap.isReady) {
      try {
        await SupabaseBootstrap.client.from('doctors').update({
          'photo_key': null,
          'photo_storage': null,
          'photo_s3_key': null,
          'photo_url': null,
          'photo_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('doctor_id', doctorId);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ProfilePhotoUploader] Supabase doctor photo clear: $e');
        }
      }
    }

    if (currentPhotoKey != null && currentPhotoKey.trim().isNotEmpty) {
      try {
        await _s3.deleteObject(currentPhotoKey.trim());
      } catch (_) {}
    }
  }

  Future<void> _persistPatientPhotoMetadata({
    required String patientId,
    required String newObjectKey,
  }) async {
    if (!SupabaseBootstrap.isReady) {
      throw StateError(
        'Cannot save profile photo: database connection is not ready.',
      );
    }

    await SupabaseBootstrap.client.from('patients').update({
      'photo_key': newObjectKey,
      'photo_storage': 's3',
      'photo_s3_key': newObjectKey,
      'photo_storage_provider': 's3',
      'photo_updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('patient_id', patientId);
    await SupabaseBootstrap.client.from('users').update({
      'photo_s3_key': newObjectKey,
      'photo_url': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('profile_id', patientId);
  }

  Future<void> _persistDoctorPhotoMetadata({
    required String doctorId,
    required String? ownerUid,
    required String newObjectKey,
  }) async {
    if (!SupabaseBootstrap.isReady) {
      throw StateError(
        'Cannot save profile photo: database connection is not ready.',
      );
    }

    await SupabaseBootstrap.client.from('doctors').update({
      'photo_key': newObjectKey,
      'photo_storage': 's3',
      'photo_s3_key': newObjectKey,
      'photo_storage_provider': 's3',
      'photo_updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('doctor_id', doctorId);
    final uid = ownerUid?.trim();
    if (uid != null && uid.isNotEmpty) {
      await SupabaseBootstrap.client.from('users').update({
        'photo_s3_key': newObjectKey,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    }
  }
}