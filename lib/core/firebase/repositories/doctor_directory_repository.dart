import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../features/patient/models/patient_models.dart';
import '../firestore_paths.dart';
import '../firebase_bootstrap.dart';
import '../firestore_query_limits.dart';
import '../firestore_read_helper.dart';
import '../../location/location_match.dart';

class DoctorDirectoryRepository {
  DoctorDirectoryRepository._();

  static final DoctorDirectoryRepository instance =
      DoctorDirectoryRepository._();

  Future<List<DoctorListing>> fetchVerifiedDoctors() async {
    return fetchAllDoctors(verifiedOnly: true);
  }

  Future<List<DoctorListing>> fetchAllDoctors(
      {bool verifiedOnly = false}) async {
    if (!FirebaseBootstrap.isReady) return const [];

    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection(FirestorePaths.doctors);
    if (verifiedOnly) {
      query = query.where('verified', isEqualTo: true);
    }

    final snapshot = await FirestoreReadHelper.getQuery(
      query: query.limit(FirestoreQueryLimits.connectionsPage * 2),
    );

    return snapshot.docs
        .map((doc) => _fromMap(doc.id, doc.data()))
        .whereType<DoctorListing>()
        .toList();
  }

  /// Real-time stream of all doctors — automatically re-emits on Firestore changes.
  Stream<List<DoctorListing>> streamAllDoctors({bool verifiedOnly = false}) {
    if (!FirebaseBootstrap.isReady) return const Stream.empty();

    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection(FirestorePaths.doctors);
    if (verifiedOnly) {
      query = query.where('verified', isEqualTo: true);
    }

    return query
        .limit(FirestoreQueryLimits.connectionsPage * 2)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => _fromMap(doc.id, doc.data()))
            .whereType<DoctorListing>()
            .toList());
  }

  Future<bool> isDoctorVerified(
    String doctorId, {
    String? ownerUid,
    bool preferCache = false,
  }) async {
    if (!FirebaseBootstrap.isReady) return false;

    try {
      // Always use a direct GET (single document read) — the security rule allows
      // the owning doctor to read their own document via ownerUid or ownsDoctor.
      // A collection LIST query is avoided because it requires a verified==true
      // filter to satisfy the list rule, which would defeat the purpose here.
      final snap = await FirestoreReadHelper.getDocument(
        reference: FirebaseFirestore.instance
            .collection(FirestorePaths.doctors)
            .doc(doctorId),
        preferCache: preferCache,
      );
      if (!snap.exists || snap.data() == null) return false;
      return _isVerifiedValue(snap.data()!['verified']);
    } catch (_) {
      return false;
    }
  }

  bool _isVerifiedValue(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  DoctorListing? _fromMap(String id, Map<String, dynamic> data) {
    try {
      final deactivated = data['deactivated'];
      if (deactivated == true ||
          (deactivated is String && deactivated.toLowerCase() == 'true')) {
        return null;
      }

      // Safely extract a string from multiple possible field names.
      String? readString(List<String> keys) {
        for (final k in keys) {
          final v = data[k];
          if (v is String && v.isNotEmpty) return v;
        }
        return null;
      }

      // Safely extract a num from multiple possible field names.
      num? readNum(List<String> keys) {
        for (final k in keys) {
          final v = data[k];
          if (v is num) return v;
          if (v is String) return num.tryParse(v);
        }
        return null;
      }

      final name = readString(['name', 'fullName', 'displayName']) ?? '';
      final docId = readString(['doctorId', 'id', 'uid']) ?? id;

      final nestedCity = readNestedAddressCity(data);
      final nestedLine1 = readNestedAddressLine1(data);
      final nestedState = () {
        final address = data['address'];
        if (address is Map) {
          final state = address['state'];
          if (state is String && state.isNotEmpty) return state;
        }
        return null;
      }();

      final listing = DoctorListing(
        id: docId,
        name: name,
        specialization: readString(['specialization', 'spec', 'specialty']) ??
            'General Physician',
        qualification: readString(['qualification', 'degree']) ?? 'MBBS',
        experienceYears:
            readNum(['experienceYears', 'experience', 'yearsExperience'])
                    ?.toInt() ??
                1,
        rating: readNum(['rating', 'avgRating'])?.toDouble() ?? 0.0,
        reviewCount:
            readNum(['reviewCount', 'reviews', 'totalReviews'])?.toInt() ?? 0,
        clinicName: readString(['clinicName', 'clinic', 'hospitalName']) ??
            '$name Clinic',
        area: nestedCity ?? readString(['area', 'locality', 'location']) ?? '',
        city: nestedCity ?? readString(['city']) ?? '',
        addressLine1: nestedLine1 ??
            readString(['addressLine1', 'address', 'addr', 'line1']) ??
            '',
        state: nestedState ??
            readString(['state', 'stateCouncil', 'stateName']) ??
            '',
        photoPath: readString(['photoPath']),
        photoUrl:
            readString(['photoUrl', 'photoURL', 'profilePhoto', 'avatarUrl']),
        distanceKm: readNum(['distanceKm', 'distance'])?.toDouble() ?? 0,
        availability: DoctorAvailability.later,
        nextSlot: readString(['nextSlot', 'slot']) ?? 'Check availability',
        verified: _isVerifiedValue(data['verified']),
        gender: readString(['gender', 'sex']) ?? 'Male',
        languages: (() {
          final raw = data['languages'];
          if (raw is List) {
            return raw
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList();
          }
          return const <String>['English', 'Hindi'];
        })(),
      );

      return listing;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[DoctorDirectoryRepository] _fromMap error for doc $id: $e\n$st');
      }
      return null;
    }
  }
}
