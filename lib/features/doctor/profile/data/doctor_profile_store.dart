import '../../../../core/firebase/firestore_service.dart';
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/constants/countries.dart';
import '../../../../core/auth/profile_completion_service.dart';
import '../../../../core/enums/user_type.dart';
import '../../../../core/firebase/firebase_bootstrap.dart';
import '../../../../core/firebase/firestore_paths.dart';
import '../../../../core/location/location_match.dart';
import '../../../../core/firebase/firestore_read_helper.dart';
// FIXED: load reviews on login/prefetch
import '../../../../core/session/doctor_session.dart';
import '../../models/doctor_models.dart';
import '../models/doctor_profile_data.dart';
import 'doctor_photo_local_store.dart';

class DoctorProfileStore extends ChangeNotifier {
  DoctorProfileStore._();

  static final DoctorProfileStore instance = DoctorProfileStore._();

  late DoctorProfileData profile = _initial;

  static String? _notificationPrefsLoadedForDoctorId;
  static Future<void>? _notificationPrefsLoadFuture;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _doctorSub;

  void reset() {
    _doctorSub?.cancel();
    _doctorSub = null;
    profile = _initial;
    resetNotificationPrefsSession();
    notifyListeners();
  }

  void listenToDoctorDocument(String doctorId) {
    if (doctorId.isEmpty || !FirebaseBootstrap.isReady) return;
    _doctorSub?.cancel();
    _doctorSub = FirebaseFirestore.instance
        .collection(FirestorePaths.doctors)
        .doc(doctorId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || snap.data() == null) return;
      final data = snap.data()!;
      final url = (data['photoUrl'] as String?) ?? (data['photoURL'] as String?);
      if (url != null && url.isNotEmpty && url != profile.photoUrl) {
        profile.photoUrl = url;
        notifyListeners();
      }
    });
  }

  static void resetNotificationPrefsSession() {
    _notificationPrefsLoadedForDoctorId = null;
    _notificationPrefsLoadFuture = null;
  }

  /// Loads notification prefs from Firestore before inbox sync applies filters.
  Future<void> ensureNotificationPrefsLoaded(String doctorId) async {
    if (doctorId.isEmpty) return;
    if (_notificationPrefsLoadedForDoctorId == doctorId) return;
    _notificationPrefsLoadFuture ??= _loadNotificationPrefs(doctorId);
    await _notificationPrefsLoadFuture;
  }

  Future<void> _loadNotificationPrefs(String doctorId) async {
    try {
      final ref = FirebaseFirestore.instance.collection(FirestorePaths.doctors).doc(doctorId);
      final snap = await FirestoreReadHelper.getDocument(
        reference: ref,
        preferCache: false,
      );
      final data = snap.data();
      if (data != null) _applyNotificationPrefsFromMap(data);
      _notificationPrefsLoadedForDoctorId = doctorId;
    } finally {
      _notificationPrefsLoadFuture = null;
    }
  }

  void _applyNotificationPrefsFromMap(Map<String, dynamic> data) {
    profile.appointmentReminders =
        data['appointmentReminders'] as bool? ?? profile.appointmentReminders;
    profile.remindHoursBefore =
        (data['remindHoursBefore'] as num?)?.toInt() ?? profile.remindHoursBefore;
    final channels = data['notificationChannels'] as List<dynamic>?;
    if (channels != null) profile.notificationChannels = channels.cast<String>();
  }

  /// Badge status for the logged-in doctor dashboard (from Firestore `verified`).
  VerificationStatus get dashboardVerificationStatus => profile.verificationStatus;

  static bool _isVerifiedValue(dynamic value) {
    if (value == true) return true;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  static VerificationStatus _verificationStatusFromFirestore(dynamic verified) {
    if (_isVerifiedValue(verified)) return VerificationStatus.verified;
    return VerificationStatus.pending;
  }

  void addPatientReview({
    required String patientName,
    required int rating,
    required String comment,
  }) {
    final parts = patientName.trim().split(RegExp(r'\s+'));
    final masked = parts.isEmpty
        ? 'Patient'
        : parts.length == 1
            ? '${parts.first[0]}.'
            : '${parts.first[0]}. ${parts.last[0]}.';
    profile.reviews.insert(
      0,
      PatientReview(
        id: 'r${DateTime.now().millisecondsSinceEpoch}',
        maskedName: masked,
        rating: rating,
        text: comment.isEmpty ? 'No written comment.' : comment,
        date: DateTime.now(),
      ),
    );
    profile.reviewCount += 1;
    final total = profile.reviews.fold<int>(0, (s, r) => s + r.rating);
    profile.rating = total / profile.reviews.length;
  }

  static final _initial = DoctorProfileData(
    fullName: '',
    specialization: '',
    verificationStatus: VerificationStatus.pending,
    rating: 0,
    reviewCount: 0,
    dateOfBirth: DateTime(1990, 1, 1),
    gender: '',
    mobile: '',
    email: '',
    languages: const [],
    qualification: '',
    superSpecialization: '',
    yearsExperience: 0,
    registrationYear: 0,
    councilNumber: '',
    stateCouncil: '',
    certifications: const [],
    awards: '',
    publications: const [],
    clinicName: '',
    clinicType: '',
    addressLine1: '',
    addressLine2: '',
    city: '',
    country: Countries.defaultCountry,
    state: '',
    pincode: '',
    mapsLink: '',
    landmark: '',
    clinicPhotoNames: const [],
    avgDurationMins: 15,
    maxPatientsPerDay: 0,
    advanceBookingDays: 7,
    autoAcceptAppointments: false,
    appointmentReminders: true,
    remindHoursBefore: 2,
    newBookingAlert: true,
    cancellationAlert: true,
    notificationChannels: const ['App'],
    twoFactorEnabled: false,
    recoveryEmail: '',
    reviews: const [],
  );

  static bool autoAcceptForDoctor(String doctorId) {
    if (doctorId == DoctorSession.loggedInDoctorId) {
      return instance.profile.autoAcceptAppointments;
    }
    return false;
  }

  static String get displayName {
    final fromProfile = instance.profile.fullName.trim();
    if (fromProfile.isNotEmpty) return fromProfile;
    final fromSession = DoctorSession.loggedInDoctorName.trim();
    if (fromSession.isNotEmpty) return fromSession;
    return 'Doctor';
  }

  static String get displayNameWithPrefix {
    var name = displayName.trim();
    final lower = name.toLowerCase();
    if (lower.startsWith('dr.')) {
      name = name.substring(3).trim();
    } else if (lower.startsWith('dr ')) {
      name = name.substring(3).trim();
    }
    return name.isEmpty ? 'Dr. Doctor' : 'Dr. $name';
  }

  void updatePhoto({String? path, Uint8List? bytes}) {
    if (path != null) profile.photoPath = path;
    if (bytes != null && bytes.isNotEmpty) {
      profile.photoBytes = bytes;
      final doctorId = DoctorSession.activeDoctorId;
      if (doctorId.isNotEmpty) {
        DoctorPhotoLocalStore.save(doctorId, bytes);
      }
    }
    notifyListeners();
  }

  /// Uploads [bytes] to Firebase Storage and saves the download URL to
  /// Firestore.  Returns the URL on success, `null` on failure.
  Future<String?> uploadPhotoToServer(String doctorId, Uint8List bytes) async {
    if (doctorId.isEmpty || bytes.isEmpty) return null;
    profile.photoBytes = bytes;
    await DoctorPhotoLocalStore.save(doctorId, bytes);

    final base64String = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$base64String';
    String? storageUrl;

    if (FirebaseBootstrap.isReady) {
      try {
        final ref = FirebaseStorage.instance.ref('doctor_profiles/$doctorId/profile.jpg');
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        storageUrl = await ref.getDownloadURL();
      } catch (e) {
        if (kDebugMode) debugPrint('[DoctorProfileStore] storage upload failed: $e');
      }

      final finalUrl = storageUrl ?? dataUrl;
      profile.photoUrl = finalUrl;
      try {
        await FirebaseFirestore.instance
            .collection(FirestorePaths.doctors)
            .doc(doctorId)
            .update({'photoUrl': finalUrl, 'photoURL': finalUrl});
      } catch (e) {
        if (kDebugMode) debugPrint('[DoctorProfileStore] firestore doc photo update failed: $e');
      }
      notifyListeners();
      return finalUrl;
    }

    profile.photoUrl = dataUrl;
    notifyListeners();
    return dataUrl;
  }

  /// Removes profile photo locally and from Firestore.
  Future<void> removePhoto(String doctorId) async {
    profile.photoPath = null;
    profile.photoBytes = null;
    profile.photoUrl = null;
    if (doctorId.isNotEmpty) {
      await DoctorPhotoLocalStore.clear(doctorId);
    }
    notifyListeners();

    if (doctorId.isNotEmpty && FirebaseBootstrap.isReady) {
      try {
        await FirebaseFirestore.instance
            .collection(FirestorePaths.doctors)
            .doc(doctorId)
            .update({
          'photoUrl': FieldValue.delete(),
          'photoURL': FieldValue.delete(),
        });
      } catch (e) {
        if (kDebugMode) debugPrint('[DoctorProfileStore] remove photo failed: $e');
      }
    }
  }

  /// Persists all editable profile fields to `doctors/{doctorId}`.
  // FIXED: profile edits were only kept in memory; now every section "Save" awaits this write.
  // NOTE: intentionally does NOT touch photo fields (storage-related), per the no-storage rule.
  Future<void> persist([String? doctorIdInput]) async {
    final doctorId = (doctorIdInput != null && doctorIdInput.isNotEmpty)
        ? doctorIdInput
        : (DoctorSession.loggedInDoctorId.isNotEmpty
            ? DoctorSession.loggedInDoctorId
            : (FirebaseAuth.instance.currentUser?.uid ?? ''));
    if (doctorId.isEmpty) {
      throw StateError('Missing doctor id — profile cannot be saved.');
    }
    final p = profile;
    final data = <String, dynamic>{
      'name': p.fullName,
      'specialization': p.specialization,
      'superSpecialization': p.superSpecialization,
      'experienceYears': p.yearsExperience,
      'registrationYear': p.registrationYear,
      'mobile': p.mobile,
      'email': p.email,
      'gender': p.gender,
      if (p.dateOfBirth != null) 'dateOfBirth': Timestamp.fromDate(p.dateOfBirth!),
      'languages': p.languages,
      'qualification': p.qualification,
      'councilNumber': p.councilNumber,
      'stateCouncil': p.stateCouncil,
      'certifications': p.certifications,
      'awards': p.awards,
      'publications': p.publications,
      'clinicName': p.clinicName,
      'clinicType': p.clinicType,
      'addressLine1': p.addressLine1,
      'addressLine2': p.addressLine2,
      'city': p.city,
      'country': p.country,
      'state': p.state,
      'pincode': p.pincode,
      'mapsLink': p.mapsLink,
      'landmark': p.landmark,
      'avgDurationMins': p.avgDurationMins,
      'maxPatientsPerDay': p.maxPatientsPerDay,
      'advanceBookingDays': p.advanceBookingDays,
      'autoAcceptAppointments': p.autoAcceptAppointments,
      'appointmentReminders': p.appointmentReminders,
      'remindHoursBefore': p.remindHoursBefore,
      'newBookingAlert': true,
      'cancellationAlert': true,
      'notificationChannels': p.notificationChannels,
      'twoFactorEnabled': p.twoFactorEnabled,
      'recoveryEmail': p.recoveryEmail,
    };
    await FirebaseFirestore.instance
        .collection(FirestorePaths.doctors)
        .doc(doctorId)
        .set(data, SetOptions(merge: true));
    if (FirebaseBootstrap.isReady) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      unawaited(
        ProfileCompletionService.instance.evaluateAndMarkFromRoleDoc(
          role: UserType.doctor,
          uid: uid,
          profileId: doctorId,
        ),
      );
    }
    notifyListeners();
  }

  /// Loads this doctor's reviews from Firestore and populates [profile.reviews].
  // FIXED: reviews were never fetched, so the Reviews screen was always empty.
  Future<void> loadReviews(String doctorId) async {
    if (doctorId.isEmpty) return;
    final fetched = await FirestoreService.instance.review.fetchForDoctor(doctorId);
    profile.reviews = fetched
        .map((r) => PatientReview(
              id: r.id,
              maskedName: r.maskedName,
              rating: r.rating,
              text: r.text,
              date: r.date,
              doctorReply: r.doctorReply,
              helpfulCount: r.helpfulCount,
            ))
        .toList();

    try {
      final ref = FirebaseFirestore.instance
          .collection(FirestorePaths.doctors)
          .doc(doctorId);
      final snap = await FirestoreReadHelper.getDocument(reference: ref, preferCache: true);
      final data = snap.data();
      if (data != null) {
        profile.rating = (data['rating'] as num?)?.toDouble() ?? profile.rating;
        profile.reviewCount = (data['reviewCount'] as num?)?.toInt() ?? profile.reviewCount;
      } else if (fetched.isNotEmpty) {
        profile.reviewCount = fetched.length;
        profile.rating = fetched.fold<double>(0, (acc, r) => acc + r.rating) / fetched.length;
      }
    } catch (_) {
      if (fetched.isNotEmpty) {
        profile.reviewCount = fetched.length;
        profile.rating = fetched.fold<double>(0, (acc, r) => acc + r.rating) / fetched.length;
      }
    }
  }

  /// Persists a doctor's reply to a review document.
  // FIXED: replies were only kept in memory; now they are written to the review doc.
  Future<void> saveReply({required String reviewId, required String reply}) async {
    if (reviewId.isEmpty) {
      throw StateError('Missing review id — reply cannot be saved.');
    }
    await FirebaseFirestore.instance
        .collection(FirestorePaths.reviews)
        .doc(reviewId)
        .update({'doctorReply': reply});
  }

  Future<void> loadFromFirestore(String doctorId) async {
    try {
      listenToDoctorDocument(doctorId);
      await loadReviews(doctorId); // FIXED: populate reviews on login/prefetch
      // Load locally-stored profile photo (on-device) so it shows everywhere.
      if (profile.photoBytes == null || profile.photoBytes!.isEmpty) {
        final localBytes = await DoctorPhotoLocalStore.load(doctorId);
        if (localBytes != null && localBytes.isNotEmpty) {
          profile.photoBytes = localBytes;
        }
      }

      final ref = FirebaseFirestore.instance.collection(FirestorePaths.doctors).doc(doctorId);
      final snap = await FirestoreReadHelper.getDocument(reference: ref, preferCache: true);
      final data = snap.data();
      if (data == null) return;

      profile.fullName = data['name'] as String? ?? profile.fullName;
      profile.specialization = data['specialization'] as String? ?? profile.specialization;
      final url = (data['photoUrl'] as String?) ?? (data['photoURL'] as String?);
      if (url != null && url.isNotEmpty) profile.photoUrl = url;
      profile.yearsExperience =
          (data['experienceYears'] as num?)?.toInt() ?? profile.yearsExperience;
      profile.registrationYear =
          (data['registrationYear'] as num?)?.toInt() ?? profile.registrationYear;
      profile.mobile = data['mobile'] as String? ?? profile.mobile;
      profile.email = data['email'] as String? ?? profile.email;
      profile.councilNumber = data['councilNumber'] as String? ?? profile.councilNumber;
      profile.stateCouncil = data['stateCouncil'] as String? ?? profile.stateCouncil;
      profile.clinicName = data['clinicName'] as String? ?? profile.clinicName;
      final nestedCity = readNestedAddressCity(data);
      if (nestedCity != null) {
        profile.city = nestedCity;
      } else {
        profile.city = data['city'] as String? ?? profile.city;
      }
      profile.rating = (data['rating'] as num?)?.toDouble() ?? profile.rating;
      profile.reviewCount = (data['reviewCount'] as num?)?.toInt() ?? profile.reviewCount;
      profile.verificationStatus = _verificationStatusFromFirestore(data['verified']);
      final langs = data['languages'] as List<dynamic>?;
      if (langs != null) {
        profile.languages = langs.cast<String>();
      }
      profile.qualification = data['qualification'] as String? ?? profile.qualification;

      // FIXED: map the remaining editable fields so saved edits survive reload.
      profile.gender = data['gender'] as String? ?? profile.gender;
      final dob = data['dateOfBirth'];
      if (dob is Timestamp) profile.dateOfBirth = dob.toDate();
      profile.superSpecialization =
          data['superSpecialization'] as String? ?? profile.superSpecialization;
      final certs = data['certifications'] as List<dynamic>?;
      if (certs != null) profile.certifications = certs.cast<String>();
      profile.awards = data['awards'] as String? ?? profile.awards;
      final pubs = data['publications'] as List<dynamic>?;
      if (pubs != null) profile.publications = pubs.cast<String>();
      profile.clinicType = data['clinicType'] as String? ?? profile.clinicType;
      profile.addressLine1 = data['addressLine1'] as String? ?? profile.addressLine1;
      profile.addressLine2 = data['addressLine2'] as String? ?? profile.addressLine2;
      final address = data['address'];
      if (address is Map) {
        final nestedLine1 = address['addressLine1'];
        if (nestedLine1 is String && nestedLine1.trim().isNotEmpty) {
          profile.addressLine1 = nestedLine1.trim();
        }
        final nestedLine2 = address['addressLine2'];
        if (nestedLine2 is String && nestedLine2.trim().isNotEmpty) {
          profile.addressLine2 = nestedLine2.trim();
        }
        final nestedState = address['state'];
        if (nestedState is String && nestedState.trim().isNotEmpty) {
          profile.state = nestedState.trim();
        }
      }
      profile.country = data['country'] as String? ?? profile.country;
      profile.state = data['state'] as String? ?? profile.state;
      profile.pincode = data['pincode'] as String? ?? profile.pincode;
      profile.mapsLink = data['mapsLink'] as String? ?? profile.mapsLink;
      profile.landmark = data['landmark'] as String? ?? profile.landmark;
      profile.avgDurationMins =
          (data['avgDurationMins'] as num?)?.toInt() ?? profile.avgDurationMins;
      profile.maxPatientsPerDay =
          (data['maxPatientsPerDay'] as num?)?.toInt() ?? profile.maxPatientsPerDay;
      profile.advanceBookingDays =
          (data['advanceBookingDays'] as num?)?.toInt() ?? profile.advanceBookingDays;
      profile.autoAcceptAppointments =
          data['autoAcceptAppointments'] as bool? ?? profile.autoAcceptAppointments;
      _applyNotificationPrefsFromMap(data);
      profile.newBookingAlert = true;
      profile.cancellationAlert = true;
      profile.twoFactorEnabled = data['twoFactorEnabled'] as bool? ?? profile.twoFactorEnabled;
      profile.recoveryEmail = data['recoveryEmail'] as String? ?? profile.recoveryEmail;
    } finally {
      notifyListeners();
    }
  }
}
