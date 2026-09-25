import '../../../core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/firebase/firebase_bootstrap.dart';
import '../models/patient_models.dart';

/// Doctors loaded from Firestore — kept in sync via a real-time stream.
class RegisteredDoctorsStore extends ChangeNotifier {
  RegisteredDoctorsStore._();

  static final RegisteredDoctorsStore instance = RegisteredDoctorsStore._();

  final List<DoctorListing> _registered = [];
  StreamSubscription<List<DoctorListing>>? _streamSub;
  StreamSubscription<User?>? _authWaitSub;
  bool _streamActive = false;
  bool _permissionDenied = false;

  List<DoctorListing> get searchableDoctors => List.unmodifiable(_registered);

  List<DoctorListing> get verifiedDoctors =>
      _registered.where((d) => d.verified).toList(growable: false);

  bool isRegistered(String doctorId) =>
      _registered.any((d) => d.id == doctorId);

  DoctorListing? findById(String doctorId) {
    for (final d in _registered) {
      if (d.id == doctorId) return d;
    }
    return null;
  }

  /// Starts a real-time Firestore stream. Safe to call multiple times —
  /// only one stream is active at a time. Retries automatically if Firebase
  /// is not yet ready.
  void startListening() {
    if (_streamActive) return;

    if (!FirebaseBootstrap.isReady) {
      // Firebase not initialised yet — retry after a short delay.
      Future.delayed(const Duration(seconds: 2), startListening);
      return;
    }

    _authWaitSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && _permissionDenied) {
        _permissionDenied = false;
        startListening();
      }
    });

    if (_permissionDenied) return;

    // Kick off a one-time fetch immediately so the UI has data fast.
    unawaited(refreshFromFirestore(verifiedOnly: true));

    _streamSub?.cancel();
    _streamActive = true;

    _streamSub = FirestoreService.instance.doctorDirectory
        .streamAllDoctors(verifiedOnly: true)
        .listen(
      (doctors) {
        if (doctors.isNotEmpty) {
          _registered
            ..clear()
            ..addAll(doctors);
          notifyListeners();
        } else if (_registered.isEmpty) {
          notifyListeners();
        }
      },
      onError: (e) {
        if (kDebugMode) debugPrint('[RegisteredDoctorsStore] stream error: $e');
        _streamActive = false;
        _streamSub?.cancel();
        _streamSub = null;
        // Rules/auth failures will not recover by retrying every 3s.
        if (e is FirebaseException && e.code == 'permission-denied') {
          _permissionDenied = true;
          return;
        }
        Future.delayed(const Duration(seconds: 3), startListening);
      },
    );
  }

  @visibleForTesting
  void markStreamActiveForTesting([bool active = true]) {
    _streamActive = active;
  }

  /// One-time fetch fallback (also used as initial fast-path).
  Future<void> refreshFromFirestore({bool verifiedOnly = true}) async {
    try {
      final doctors = await FirestoreService.instance.doctorDirectory
          .fetchAllDoctors(verifiedOnly: verifiedOnly);
      if (doctors.isNotEmpty) {
        _registered
          ..clear()
          ..addAll(doctors);
        notifyListeners();
      } else if (_registered.isEmpty) {
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RegisteredDoctorsStore] fetch error: $e');
      // Always notify so UI doesn't stay stuck loading.
      notifyListeners();
    }
  }

  void addFromRegistration(DoctorListing listing) {
    if (!_registered.any((d) => d.id == listing.id)) {
      _registered.add(listing);
      notifyListeners();
    }
  }

  /// Keeps search/profile cards in sync after a new patient review.
  void updateDoctorRating({
    required String doctorId,
    required double rating,
    required int reviewCount,
  }) {
    final index = _registered.indexWhere((d) => d.id == doctorId);
    if (index < 0) return;
    final current = _registered[index];
    _registered[index] = DoctorListing(
      id: current.id,
      name: current.name,
      specialization: current.specialization,
      qualification: current.qualification,
      experienceYears: current.experienceYears,
      rating: rating,
      reviewCount: reviewCount,
      clinicName: current.clinicName,
      area: current.area,
      distanceKm: current.distanceKm,
      availability: current.availability,
      nextSlot: current.nextSlot,
      verified: current.verified,
      gender: current.gender,
      languages: current.languages,
      addressLine1: current.addressLine1,
      state: current.state,
      city: current.city,
      photoPath: current.photoPath,
      photoUrl: current.photoUrl,
    );
    notifyListeners();
  }
}
