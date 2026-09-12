import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/shared_appointments_store.dart';
import '../../../core/session/patient_session.dart';
import '../appointments/models/patient_appointment_models.dart';
import '../lab/models/lab_models.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../records/data/patient_lab_booking_store.dart';
import 'registered_doctors_store.dart';

class SavedLabEntry {
  const SavedLabEntry({
    this.id,
    required this.name,
    required this.rating,
    required this.area,
  });

  final String? id;
  final String name;
  final double rating;
  final String area;

  String get key => (id?.trim().isNotEmpty == true ? id! : name.trim().toLowerCase());

  PartnerLab toPartnerLab() => PartnerLab(id: id, name: name, rating: rating, area: area);

  Map<String, dynamic> toMap() => {
        if (id != null && id!.trim().isNotEmpty) 'id': id,
        'name': name,
        'rating': rating,
        'area': area,
      };

  factory SavedLabEntry.fromMap(Map<String, dynamic> data) {
    return SavedLabEntry(
      id: data['id'] as String?,
      name: data['name'] as String? ?? '',
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      area: data['area'] as String? ?? '',
    );
  }

  factory SavedLabEntry.fromPartnerLab(PartnerLab lab) {
    return SavedLabEntry(
      id: lab.id,
      name: lab.name,
      rating: lab.rating,
      area: lab.area,
    );
  }

  factory SavedLabEntry.fromRegisteredLab(RegisteredLabProfile lab) {
    return SavedLabEntry(
      id: lab.id,
      name: lab.labName,
      rating: lab.rating > 0 ? lab.rating : 4.5,
      area: lab.area.isNotEmpty ? lab.area : lab.address,
    );
  }
}

class SavedDoctorEntry {
  const SavedDoctorEntry({
    required this.id,
    required this.name,
    required this.specialization,
    this.rating = 0,
    this.reviewCount = 0,
    this.city = '',
    this.photoUrl,
    this.photoPath,
  });

  final String id;
  final String name;
  final String specialization;
  final double rating;
  final int reviewCount;
  final String city;
  final String? photoUrl;
  final String? photoPath;

  MyDoc toMyDoc() => MyDoc(
        id: id,
        name: name,
        specialization: specialization,
        rating: rating,
        reviewCount: reviewCount,
        city: city,
        photoUrl: photoUrl,
        photoPath: photoPath,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'specialization': specialization,
        'rating': rating,
        'reviewCount': reviewCount,
        'city': city,
        if (photoUrl != null && photoUrl!.trim().isNotEmpty) 'photoUrl': photoUrl,
        if (photoPath != null && photoPath!.trim().isNotEmpty) 'photoPath': photoPath,
      };

  factory SavedDoctorEntry.fromMap(Map<String, dynamic> data) {
    return SavedDoctorEntry(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      specialization: data['specialization'] as String? ?? '',
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (data['reviewCount'] as num?)?.toInt() ?? 0,
      city: data['city'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      photoPath: data['photoPath'] as String?,
    );
  }

  factory SavedDoctorEntry.fromListing(DoctorListing listing) {
    return SavedDoctorEntry(
      id: listing.id,
      name: listing.name,
      specialization: listing.specialization,
      rating: listing.rating,
      reviewCount: listing.reviewCount,
      city: listing.area,
      photoUrl: listing.photoUrl,
      photoPath: listing.photoPath,
    );
  }
}

class PatientFavoritesStore extends ChangeNotifier {
  PatientFavoritesStore._();

  static final PatientFavoritesStore instance = PatientFavoritesStore._();

  final Set<String> _hiddenDoctorIds = {};
  final Set<String> _hiddenLabKeys = {};
  final List<String> _addedDoctorIds = [];
  final Map<String, SavedDoctorEntry> _addedDoctorSnapshots = {};
  final List<SavedLabEntry> _addedLabs = [];

  Set<String> get hiddenDoctorIds => Set.unmodifiable(_hiddenDoctorIds);
  Set<String> get hiddenLabKeys => Set.unmodifiable(_hiddenLabKeys);
  List<String> get addedDoctorIds => List.unmodifiable(_addedDoctorIds);
  List<SavedLabEntry> get addedLabs => List.unmodifiable(_addedLabs);

  void clear() {
    _hiddenDoctorIds.clear();
    _hiddenLabKeys.clear();
    _addedDoctorIds.clear();
    _addedDoctorSnapshots.clear();
    _addedLabs.clear();
    notifyListeners();
  }
  List<Map<String, dynamic>> get addedDoctorsForPersist => _addedDoctorIds
      .map((id) => _addedDoctorSnapshots[id]?.toMap())
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);

  void applyFromPatientData(Map<String, dynamic>? data) {
    _hiddenDoctorIds
      ..clear()
      ..addAll(
        (data?['hiddenDoctorIds'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .where((id) => id.trim().isNotEmpty),
      );

    _hiddenLabKeys
      ..clear()
      ..addAll(
        (data?['hiddenLabKeys'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .where((key) => key.trim().isNotEmpty),
      );

    final localAddedDoctorIds = List<String>.from(_addedDoctorIds);
    final localDoctorSnapshots = Map<String, SavedDoctorEntry>.from(_addedDoctorSnapshots);
    final remoteAddedDoctorIds = (data?['addedDoctorIds'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .where((id) => id.trim().isNotEmpty);

    _addedDoctorIds
      ..clear()
      ..addAll({...localAddedDoctorIds, ...remoteAddedDoctorIds});

    _addedDoctorSnapshots
      ..clear()
      ..addAll(localDoctorSnapshots)
      ..addAll(
        Map<String, SavedDoctorEntry>.fromEntries(
          (data?['addedDoctors'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((item) => SavedDoctorEntry.fromMap(Map<String, dynamic>.from(item)))
              .where((entry) => entry.id.trim().isNotEmpty)
              .map((entry) => MapEntry(entry.id, entry)),
        ),
      );

    for (final id in _addedDoctorIds) {
      _ensureDoctorSnapshot(id);
    }

    _addedLabs
      ..clear()
      ..addAll(
        (data?['addedLabs'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => SavedLabEntry.fromMap(Map<String, dynamic>.from(item))),
      );
    notifyListeners();
  }

  PatientAppointment? _latestAppointmentFor(String doctorId) {
    for (final appointment in _visitedAppointments()) {
      if (appointment.doctorId == doctorId) return appointment;
    }
    return null;
  }

  List<PatientAppointment> _visitedAppointments() {
    return SharedAppointmentsStore.instance
        .patientAppointments()
        .where((appointment) => appointment.cancellationReason == null)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  List<String> visitedDoctorIds() {
    final ids = <String>[];
    for (final appointment in _visitedAppointments()) {
      if (appointment.doctorId.trim().isEmpty) continue;
      if (!ids.contains(appointment.doctorId)) ids.add(appointment.doctorId);
    }
    return ids;
  }

  List<SavedLabEntry> visitedLabs() {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return const [];

    final labs = <SavedLabEntry>[];
    final seen = <String>{};
    for (final booking in PatientLabBookingStore.instance.forPatient(patientId)) {
      final name = booking.labName?.trim() ?? '';
      if (name.isEmpty) continue;
      final entry = SavedLabEntry(
        id: booking.labId,
        name: name,
        rating: 0,
        area: booking.address.trim(),
      );
      if (!seen.add(entry.key)) continue;
      labs.add(entry);
    }
    return labs;
  }

  List<String> _visibleDoctorIds() {
    final ids = <String>[];
    for (final id in visitedDoctorIds()) {
      if (_hiddenDoctorIds.contains(id)) continue;
      ids.add(id);
    }
    for (final id in _addedDoctorIds) {
      if (ids.contains(id)) continue;
      ids.add(id);
    }
    return ids;
  }

  List<SavedLabEntry> _allLabEntries() {
    final labs = <SavedLabEntry>[];
    final seen = <String>{};

    void addEntry(SavedLabEntry entry) {
      if (entry.name.trim().isEmpty) return;
      if (!seen.add(entry.key)) return;
      labs.add(entry);
    }

    for (final lab in visitedLabs()) {
      addEntry(lab);
    }
    for (final lab in _addedLabs) {
      addEntry(lab);
    }
    return labs;
  }

  bool isDoctorVisible(String doctorId) => _visibleDoctorIds().contains(doctorId);

  bool isLabVisible(SavedLabEntry lab) {
    if (_hiddenLabKeys.contains(lab.key)) return false;
    return _allLabEntries().any((item) => item.key == lab.key);
  }

  MyDoc? _doctorFromId(String doctorId) {
    final store = RegisteredDoctorsStore.instance;
    final listing = store.findById(doctorId);
    if (listing != null) {
      _rememberDoctorSnapshot(SavedDoctorEntry.fromListing(listing));
      return MyDoc(
        id: listing.id,
        name: listing.name,
        specialization: listing.specialization,
        rating: listing.rating,
        reviewCount: listing.reviewCount,
        city: listing.area,
        photoUrl: listing.photoUrl,
        photoPath: listing.photoPath,
      );
    }

    final snapshot = _addedDoctorSnapshots[doctorId];
    if (snapshot != null) {
      return snapshot.toMyDoc();
    }

    final appointment = _latestAppointmentFor(doctorId);
    if (appointment != null) {
      return MyDoc(
        id: doctorId,
        name: appointment.doctorName,
        specialization: appointment.specialization,
        rating: 0,
        reviewCount: 0,
        city: '',
      );
    }

    return null;
  }

  List<MyDoc> visibleDoctors() {
    return _visibleDoctorIds()
        .map(_doctorFromId)
        .whereType<MyDoc>()
        .toList(growable: false);
  }

  List<SavedLabEntry> visibleLabs() {
    return _allLabEntries().where((lab) => !_hiddenLabKeys.contains(lab.key)).toList();
  }

  Future<void> addDoctor(String doctorId) async {
    if (doctorId.trim().isEmpty) return;

    final listing = RegisteredDoctorsStore.instance.findById(doctorId);

    if (_hiddenDoctorIds.remove(doctorId)) {
      if (listing != null) {
        _rememberDoctorSnapshot(SavedDoctorEntry.fromListing(listing));
      }
      notifyListeners();
      await _persist();
      return;
    }

    if (isDoctorVisible(doctorId)) return;

    if (listing == null && !visitedDoctorIds().contains(doctorId)) {
      return;
    }

    if (!_addedDoctorIds.contains(doctorId)) {
      _addedDoctorIds.add(doctorId);
      if (listing != null) {
        _rememberDoctorSnapshot(SavedDoctorEntry.fromListing(listing));
      } else {
        _ensureDoctorSnapshot(doctorId);
      }
      notifyListeners();
      await _persist();
    }
  }

  Future<void> removeDoctor(String doctorId) async {
    if (doctorId.trim().isEmpty) return;

    var changed = false;
    if (_addedDoctorIds.remove(doctorId)) {
      changed = true;
      _addedDoctorSnapshots.remove(doctorId);
    }
    if (visitedDoctorIds().contains(doctorId) && _hiddenDoctorIds.add(doctorId)) {
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await _persist();
  }

  Future<void> addLab(SavedLabEntry lab) async {
    if (lab.name.trim().isEmpty) return;

    if (_hiddenLabKeys.remove(lab.key)) {
      notifyListeners();
      await _persist();
      return;
    }

    if (isLabVisible(lab)) return;

    if (!_addedLabs.any((item) => item.key == lab.key)) {
      _addedLabs.add(lab);
      notifyListeners();
      await _persist();
    }
  }

  Future<void> removeLab(String key) async {
    if (key.trim().isEmpty) return;

    var changed = false;
    final beforeAdded = _addedLabs.length;
    _addedLabs.removeWhere((lab) => lab.key == key);
    if (_addedLabs.length != beforeAdded) changed = true;

    final isVisited = visitedLabs().any((lab) => lab.key == key);
    if (isVisited && _hiddenLabKeys.add(key)) changed = true;

    if (!changed) return;
    notifyListeners();
    await _persist();
  }

  Future<List<SavedLabEntry>> registeredLabsForSearch() async {
    final registered = await FirestoreService.instance.lab.fetchVerifiedLabs();
    if (registered.isNotEmpty) {
      return registered.map(SavedLabEntry.fromRegisteredLab).toList(growable: false);
    }

    final catalog = await FirestoreService.instance.labCatalog.fetchCatalog();
    return catalog.partnerLabs.map(SavedLabEntry.fromPartnerLab).toList(growable: false);
  }

  Future<void> _persist() async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return;
    await FirestoreService.instance.patientProfile.savePatientDocument(patientId, {
      'hiddenDoctorIds': _hiddenDoctorIds.toList(),
      'hiddenLabKeys': _hiddenLabKeys.toList(),
      'addedDoctorIds': _addedDoctorIds,
      'addedDoctors': _addedDoctorIds
          .map((id) => _addedDoctorSnapshots[id]?.toMap())
          .whereType<Map<String, dynamic>>()
          .toList(),
      'addedLabs': _addedLabs.map((lab) => lab.toMap()).toList(),
    });
  }

  void _rememberDoctorSnapshot(SavedDoctorEntry entry) {
    if (entry.id.trim().isEmpty) return;
    _addedDoctorSnapshots[entry.id] = entry;
  }

  void _ensureDoctorSnapshot(String doctorId) {
    if (_addedDoctorSnapshots.containsKey(doctorId)) return;
    final listing = RegisteredDoctorsStore.instance.findById(doctorId);
    if (listing != null) {
      _rememberDoctorSnapshot(SavedDoctorEntry.fromListing(listing));
    }
  }
}
