import 'dart:async';

import '../../../core/auth/profile_completion_service.dart';
import '../../../core/enums/user_type.dart';
import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/session/medical_store_session.dart';
import '../models/pharmacy_models.dart';

class MedicalStoreRegistry extends ChangeNotifier {
  MedicalStoreRegistry._();

  static final MedicalStoreRegistry instance = MedicalStoreRegistry._();

  final List<MedicalStoreProfile> _stores = [];

  static List<MedicalStoreProfile> get all =>
      List.unmodifiable(instance._stores);

  static MedicalStoreProfile? findById(String id) {
    for (final s in instance._stores) {
      if (s.id == id) return s;
    }
    return null;
  }

  static Future<void> refreshFromFirestore({bool preferCache = true}) async {
    final stores =
        await FirestoreService.instance.medicalStore.fetchVerifiedStores(
      preferCache: preferCache,
    );
    instance._stores
      ..clear()
      ..addAll(stores);
    instance.notifyListeners();
  }

  static Future<void> ensureStoreLoaded(String storeId) async {
    if (storeId.isEmpty || findById(storeId) != null) return;
    final remote =
        await FirestoreService.instance.medicalStore.fetchStoreById(storeId);
    if (remote == null) return;
    instance._stores.add(remote);
    instance.notifyListeners();
  }

  static String register({
    required String storeName,
    required String ownerName,
    required String address,
    required String drugLicenseNumber,
    required String phone,
    required String email,
    String? gstNumber,
  }) {
    final id = 'ms${DateTime.now().millisecondsSinceEpoch}';
    instance._stores.add(
      MedicalStoreProfile(
        id: id,
        storeName: storeName,
        ownerName: ownerName,
        address: address,
        drugLicenseNumber: drugLicenseNumber,
        gstNumber: gstNumber,
        phone: phone,
        email: email,
      ),
    );
    instance.notifyListeners();
    return id;
  }

  static Future<String?> updateStoreProfile({
    required String storeId,
    String? storeName,
    String? phone,
    String? email,
    String? gstNumber,
    bool clearGstNumber = false,
    String? addressLine1,
    String? addressLine2,
    String? country,
    String? state,
    String? city,
    String? pincode,
  }) async {
    var index = instance._stores.indexWhere((s) => s.id == storeId);
    if (index < 0) {
      final remote =
          await FirestoreService.instance.medicalStore.fetchStoreById(storeId);
      if (remote == null) return 'Store not found';
      instance._stores.add(remote);
      index = instance._stores.length - 1;
    }

    final current = instance._stores[index];
    final normalizedEmail = email?.trim().toLowerCase();
    Map<String, dynamic>? addressMap;
    String? addressStr;
    if (addressLine1 != null) {
      addressMap = {
        'addressLine1': addressLine1,
        'addressLine2': addressLine2 ?? '',
        'country': country ?? '',
        'state': state ?? '',
        'city': city ?? '',
        'pinCode': pincode ?? '',
      };
      final parts = [
        addressLine1,
        addressLine2 ?? '',
        city ?? '',
        state ?? '',
        pincode ?? ''
      ].where((e) => e.isNotEmpty);
      addressStr = parts.join(', ');
    }

    try {
      await FirestoreService.instance.medicalStore.updateStoreFields(
        storeId,
        storeName: storeName,
        address: addressMap,
        phone: phone,
        email: normalizedEmail,
        gstNumber: gstNumber,
        clearGstNumber: clearGstNumber,
      );
    } catch (_) {
      if (FirebaseBootstrap.isReady) {
        return 'Could not save changes. Please try again.';
      }
    }

    instance._stores[index] = current.copyWith(
      storeName: storeName,
      address: addressStr,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      country: country,
      state: state,
      city: city,
      pincode: pincode,
      phone: phone,
      email: normalizedEmail,
      gstNumber: gstNumber,
      clearGstNumber: clearGstNumber,
    );
    if (storeName != null && storeId == MedicalStoreSession.loggedInStoreId) {
      MedicalStoreSession.setStore(id: storeId, name: storeName);
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    unawaited(
      ProfileCompletionService.instance.evaluateAndMarkFromRoleDoc(
        role: UserType.medicalStore,
        uid: uid,
        profileId: storeId,
      ),
    );
    instance.notifyListeners();
    return null;
  }
}
