import 'package:cloud_firestore/cloud_firestore.dart';

import '../../enums/user_type.dart';
import '../../supabase/supabase_bootstrap.dart';
import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import 'doctor_account_repository.dart';

/// Shared admin-approval and provider lifecycle gate for all account roles.
class RoleAccountRepository {
  RoleAccountRepository._();

  static final RoleAccountRepository instance = RoleAccountRepository._();

  static const underReviewLoginMessage =
      'Your account is under review. Our team will verify it within 24–48 hours.';

  static const underReviewRegistrationMessage =
      'Thank you for registering. Our team will verify your account within 24–48 hours. You can sign in after approval.';

  Future<bool> isVerified(
    UserType role,
    String profileId, {
    bool preferCache = false,
  }) async {
    return switch (role) {
      UserType.superAdmin => true,
      UserType.doctor => await DoctorAccountRepository.instance.isVerified(
          profileId,
          preferCache: preferCache,
        ),
      UserType.patient => true,
      UserType.lab => true,
      UserType.medicalStore || UserType.medical => true,
      UserType.ambulance => true,
    };
  }

  /// Deactivates provider profile across Supabase (RPC) and Firestore
  Future<void> deactivateProvider({
    required UserType role,
    required String profileId,
    required String ownerUid,
  }) async {
    if (role == UserType.doctor) {
      await DoctorAccountRepository.instance.deactivate(
        doctorId: profileId,
        ownerUid: ownerUid,
      );
      return;
    }

    if (SupabaseBootstrap.isReady) {
      await SupabaseBootstrap.client.rpc('deactivate_provider_profile');
    }

    if (FirebaseBootstrap.isReady) {
      final collectionName = switch (role) {
        UserType.lab => FirestorePaths.labs,
        UserType.medicalStore || UserType.medical => FirestorePaths.medicalStores,
        UserType.ambulance => FirestorePaths.ambulances,
        _ => null,
      };
      if (collectionName != null) {
        final batch = FirebaseFirestore.instance.batch();
        batch.update(
          FirebaseFirestore.instance.collection(collectionName).doc(profileId),
          {
            'deactivated': true,
            'verified': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        batch.update(
          FirebaseFirestore.instance.collection(FirestorePaths.users).doc(ownerUid),
          {
            'deactivated': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        await batch.commit();
      }
    }
  }

  /// Reactivates provider profile across Supabase (RPC) and Firestore
  Future<void> reactivateProvider({
    required UserType role,
    required String profileId,
    required String ownerUid,
  }) async {
    if (role == UserType.doctor) {
      await DoctorAccountRepository.instance.reactivate(
        doctorId: profileId,
        ownerUid: ownerUid,
      );
      return;
    }

    if (SupabaseBootstrap.isReady) {
      await SupabaseBootstrap.client.rpc('reactivate_provider_profile');
    }

    if (FirebaseBootstrap.isReady) {
      final collectionName = switch (role) {
        UserType.lab => FirestorePaths.labs,
        UserType.medicalStore || UserType.medical => FirestorePaths.medicalStores,
        UserType.ambulance => FirestorePaths.ambulances,
        _ => null,
      };
      if (collectionName != null) {
        final batch = FirebaseFirestore.instance.batch();
        batch.update(
          FirebaseFirestore.instance.collection(collectionName).doc(profileId),
          {
            'deactivated': false,
            'verified': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        batch.update(
          FirebaseFirestore.instance.collection(FirestorePaths.users).doc(ownerUid),
          {
            'deactivated': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        await batch.commit();
      }
    }
  }
}

typedef RoleAccountFirestore = RoleAccountRepository;
