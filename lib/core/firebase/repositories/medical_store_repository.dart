import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/pharmacy/models/pharmacy_models.dart';
import '../firestore_paths.dart';
import '../firebase_bootstrap.dart';
import '../firestore_query_limits.dart';
import '../firestore_read_helper.dart';

class MedicalStoreRepository {
  MedicalStoreRepository._();

  static final MedicalStoreRepository instance = MedicalStoreRepository._();

  Future<bool> isStoreVerified(String storeId) async {
    if (!FirebaseBootstrap.isReady) return false;
    final snap = await FirestoreReadHelper.getDocument(
      reference: FirebaseFirestore.instance
          .collection(FirestorePaths.medicalStores)
          .doc(storeId),
      preferCache: false,
    );
    if (!snap.exists || snap.data() == null) return false;
    return snap.data()!['verified'] as bool? ?? false;
  }

  Future<List<MedicalStoreProfile>> fetchVerifiedStores(
      {bool preferCache = true}) async {
    if (!FirebaseBootstrap.isReady) return const [];

    final snapshot = await FirestoreReadHelper.getQuery(
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.medicalStores)
          .where('verified',
              isEqualTo: true) // FIXED: only surface admin-verified stores
          .limit(FirestoreQueryLimits.verifiedDirectoryListingCap),
      preferCache: preferCache,
    );

    return snapshot.docs
        .map((doc) => _fromMap(doc.id, doc.data()))
        .whereType<MedicalStoreProfile>()
        .toList();
  }

  MedicalStoreProfile? _fromMap(String id, Map<String, dynamic> data) {
    try {
      final addressData = data['address'];
      String addressStr = '';
      String aCountry = '';
      String aState = '';
      String aCity = data['city'] as String? ?? '';
      String aLine1 = '';
      String aLine2 = '';
      String aPinCode = '';

      if (addressData is Map) {
        aCountry = addressData['country'] as String? ?? '';
        aState = addressData['state'] as String? ?? '';
        aCity = addressData['city'] as String? ?? aCity;
        aLine1 = addressData['addressLine1'] as String? ?? '';
        aLine2 = addressData['addressLine2'] as String? ?? '';
        aPinCode = addressData['pinCode'] as String? ?? '';

        final parts = [aLine1, aLine2, aCity, aState, aPinCode]
            .where((e) => e.isNotEmpty);
        addressStr = parts.join(', ');
      } else if (addressData is String) {
        addressStr = addressData;
      }

      return MedicalStoreProfile(
        id: data['storeId'] as String? ?? id,
        storeName: data['storeName'] as String? ?? '',
        ownerName: data['ownerName'] as String? ?? '',
        address: addressStr,
        city: aCity,
        addressLine1: aLine1,
        addressLine2: aLine2,
        country: aCountry,
        state: aState,
        pincode: aPinCode,
        drugLicenseNumber: (data['drugLicenseNumber'] as String?) ??
            (data['licenseNumber'] as String?) ??
            '',
        phone: data['phone'] as String? ?? '',
        email: data['email'] as String? ?? '',
        gstNumber: _optionalGst(data['gstNumber'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _optionalGst(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<MedicalStoreProfile?> fetchStoreById(String storeId) async {
    if (!FirebaseBootstrap.isReady || storeId.isEmpty) return null;

    final snap = await FirestoreReadHelper.getDocument(
      reference: FirebaseFirestore.instance
          .collection(FirestorePaths.medicalStores)
          .doc(storeId),
      preferCache: false,
    );
    if (!snap.exists || snap.data() == null) return null;
    return _fromMap(snap.id, snap.data()!);
  }

  Future<void> updateStoreFields(
    String storeId, {
    String? storeName,
    Map<String, dynamic>? address,
    String? phone,
    String? email,
    String? gstNumber,
    bool clearGstNumber = false,
  }) async {
    if (!FirebaseBootstrap.isReady || storeId.isEmpty) return;

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (storeName != null) updates['storeName'] = storeName;
    if (address != null) updates['address'] = address;
    if (phone != null) updates['phone'] = phone;
    if (email != null) updates['email'] = email.trim().toLowerCase();
    if (clearGstNumber) {
      updates['gstNumber'] = FieldValue.delete();
    } else if (gstNumber != null) {
      updates['gstNumber'] = gstNumber;
    }

    if (updates.length == 1) return;

    await FirebaseFirestore.instance
        .collection(FirestorePaths.medicalStores)
        .doc(storeId)
        .set(updates, SetOptions(merge: true));
  }
}
