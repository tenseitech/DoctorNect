import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_query_limits.dart';
import '../firestore_read_helper.dart';

/// Registered diagnostic lab profile.
class RegisteredLabProfile {
  const RegisteredLabProfile({
    required this.id,
    required this.labName,
    required this.address,
    required this.licenseNumber,
    this.phone = '',
    this.email = '',
    this.gstNumber,
    this.rating = 0,
    this.area = '',
    this.verified = false,
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.country = '',
    this.state = '',
    this.city = '',
    this.pincode = '',
  });

  final String id;
  final String labName;
  final String address;
  final String licenseNumber;
  final String phone;
  final String email;
  final String? gstNumber;
  final double rating;
  final String area;
  final bool verified;
  final String addressLine1;
  final String addressLine2;
  final String country;
  final String state;
  final String city;
  final String pincode;

  RegisteredLabProfile copyWith({
    String? labName,
    String? address,
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
  }) {
    return RegisteredLabProfile(
      id: id,
      labName: labName ?? this.labName,
      address: address ?? this.address,
      licenseNumber: licenseNumber,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      gstNumber: clearGstNumber ? null : (gstNumber ?? this.gstNumber),
      rating: rating,
      area: area,
      verified: verified,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      country: country ?? this.country,
      state: state ?? this.state,
      city: city ?? this.city,
      pincode: pincode ?? this.pincode,
    );
  }
}

class LabRepository {
  LabRepository._();

  static final LabRepository instance = LabRepository._();

  Future<bool> isLabVerified(String labId) async {
    if (!FirebaseBootstrap.isReady || labId.isEmpty) return false;
    final snap = await FirestoreReadHelper.getDocument(
      reference: FirebaseFirestore.instance.collection(FirestorePaths.labs).doc(labId),
      preferCache: false,
    );
    if (!snap.exists || snap.data() == null) return false;
    return snap.data()!['verified'] as bool? ?? false; // FIXED: gate login on admin verification
  }

  Future<RegisteredLabProfile?> fetchLabById(String labId, {bool preferCache = true}) async {
    if (!FirebaseBootstrap.isReady || labId.isEmpty) return null;
    final snap = await FirestoreReadHelper.getDocument(
      reference: FirebaseFirestore.instance.collection(FirestorePaths.labs).doc(labId),
      preferCache: preferCache,
    );
    if (!snap.exists || snap.data() == null) return null;
    return _fromMap(snap.id, snap.data()!);
  }

  Future<List<RegisteredLabProfile>> fetchVerifiedLabs({bool preferCache = true}) async {
    if (!FirebaseBootstrap.isReady) return const [];

    final snapshot = await FirestoreReadHelper.getQuery(
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.labs)
          .where('verified', isEqualTo: true) // FIXED: only surface admin-verified labs to doctors/patients
          .limit(FirestoreQueryLimits.verifiedDirectoryListingCap),
      preferCache: preferCache,
    );

    return snapshot.docs
        .map((doc) => _fromMap(doc.id, doc.data()))
        .whereType<RegisteredLabProfile>()
        .toList();
  }

  RegisteredLabProfile? _fromMap(String id, Map<String, dynamic> data) {
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
        
        final parts = [aLine1, aLine2, aCity, aState, aPinCode].where((e) => e.isNotEmpty);
        addressStr = parts.join(', ');
      } else if (addressData is String) {
        addressStr = addressData;
      }

      return RegisteredLabProfile(
        id: data['labId'] as String? ?? id,
        labName: data['labName'] as String? ?? data['name'] as String? ?? '',
        address: addressStr,
        addressLine1: aLine1,
        addressLine2: aLine2,
        country: aCountry,
        state: aState,
        city: aCity,
        pincode: aPinCode,
        licenseNumber: data['licenseNumber'] as String? ?? '',
        phone: data['phone'] as String? ?? '',
        email: data['email'] as String? ?? '',
        gstNumber: _optionalGst(data['gstNumber'] as String?),
        rating: (data['rating'] as num?)?.toDouble() ?? 0,
        area: aCity.isNotEmpty ? aCity : (data['area'] as String? ?? data['city'] as String? ?? ''),
        verified: data['verified'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _optionalGst(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> updateLabFields(
    String labId, {
    String? labName,
    Map<String, dynamic>? address,
    String? phone,
    String? email,
    String? gstNumber,
    bool clearGstNumber = false,
  }) async {
    if (!FirebaseBootstrap.isReady || labId.isEmpty) return;

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (labName != null) {
      updates['labName'] = labName;
      updates['name'] = labName;
    }
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
        .collection(FirestorePaths.labs)
        .doc(labId)
        .set(updates, SetOptions(merge: true));
  }
}
