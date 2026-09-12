import '../../../../core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/firebase/models/doctor_medical_directory_entry.dart';
import '../../../../core/session/doctor_session.dart';

/// Per-doctor medical directory (labs, specialists, ambulances, etc.).
class MedicalDirectoryStore extends ChangeNotifier {
  MedicalDirectoryStore._();

  static final MedicalDirectoryStore instance = MedicalDirectoryStore._();

  final List<DoctorMedicalDirectoryEntry> _entries = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastPage;
  bool _hasMore = true;
  bool _loading = false;

  List<DoctorMedicalDirectoryEntry> get all => List.unmodifiable(_entries);
  bool get hasMore => _hasMore;
  bool get isLoading => _loading;

  List<DoctorMedicalDirectoryEntry> forDoctor(String doctorId) {
    return _entries.where((e) => e.doctorId == doctorId).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void add(DoctorMedicalDirectoryEntry entry) {
    _entries.removeWhere((e) => e.entryId == entry.entryId);
    _entries.add(entry);
    _entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    unawaited(FirestoreService.instance.medicalDirectory.save(entry));
  }

  void update(DoctorMedicalDirectoryEntry entry) {
    _entries.removeWhere((e) => e.entryId == entry.entryId);
    _entries.add(entry);
    _entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    unawaited(FirestoreService.instance.medicalDirectory.update(entry));
  }

  void remove(String entryId) {
    _entries.removeWhere((e) => e.entryId == entryId);
    notifyListeners();
    unawaited(FirestoreService.instance.medicalDirectory.delete(entryId));
  }

  void mergeFromFirestore(List<DoctorMedicalDirectoryEntry> remote) {
    for (final remoteEntry in remote) {
      _entries.removeWhere((e) => e.entryId == remoteEntry.entryId);
      _entries.add(remoteEntry);
    }
    _entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
  }

  Future<void> refreshForDoctor({bool preferCache = true}) async {
    final doctorId = DoctorSession.loggedInDoctorId;
    if (preferCache && forDoctor(doctorId).isNotEmpty) return;

    _lastPage = null;
    _hasMore = true;
    await loadMoreForDoctor(preferCache: preferCache);
  }

  Future<void> loadMoreForDoctor({bool preferCache = true}) async {
    if (!_hasMore || _loading) return;
    _loading = true;
    notifyListeners();

    try {
      final page = await FirestoreService.instance.medicalDirectory.fetchForDoctor(
        DoctorSession.loggedInDoctorId,
        startAfter: _lastPage,
        preferCache: preferCache,
      );
      mergeFromFirestore(page.items);
      _lastPage = page.lastDocument;
      _hasMore = page.hasMore;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
