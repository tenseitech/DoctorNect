import '../../../../core/firebase/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/foundation.dart';

import '../../../../core/session/doctor_session.dart';
import '../../../../core/supabase/supabase_bootstrap.dart';
import '../../../../core/supabase/supabase_patient_repository.dart';
import '../../../../core/supabase/mappers/prescription_supabase_mapper.dart';
import '../models/clinical_models.dart';
import '../../profile/data/doctor_profile_store.dart';

/// In-memory EMR store for saved prescriptions (single source of truth).

class ClinicalPrescriptionStore extends ChangeNotifier {
  ClinicalPrescriptionStore._();

  static final ClinicalPrescriptionStore instance =
      ClinicalPrescriptionStore._();

  final List<PrescriptionDraft> _records = [];

  DocumentSnapshot<Map<String, dynamic>>? _lastDoctorPage;

  DocumentSnapshot<Map<String, dynamic>>? _lastPatientPage;

  bool _hasMoreDoctor = true;

  bool _hasMorePatient = true;

  List<PrescriptionDraft> get all => List.unmodifiable(_records);

  bool get hasMoreDoctor => _hasMoreDoctor;

  bool get hasMorePatient => _hasMorePatient;

  void clear() {
    _records.clear();
    _lastDoctorPage = null;
    _lastPatientPage = null;
    _hasMoreDoctor = true;
    _hasMorePatient = true;
    notifyListeners();
  }

  PrescriptionDraft? findById(String prescriptionId) {
    for (final draft in _records) {
      if (draft.prescriptionId == prescriptionId) return draft;
    }

    return null;
  }

  List<PrescriptionDraft> forPatient(String patientId) {
    return _records.where((d) => d.patientId == patientId).toList()
      ..sort((a, b) => b.prescriptionDate.compareTo(a.prescriptionDate));
  }

  bool _hasPatientRecords(String patientId) =>
      _records.any((r) => r.patientId == patientId);

  bool get _isDoctorContext => DoctorSession.loggedInDoctorId.isNotEmpty;

  void _purgePatientPrescriptions(String patientId) {
    final hadRecords = _records.any((d) => d.patientId == patientId);
    _records.removeWhere((d) => d.patientId == patientId);
    if (hadRecords) notifyListeners();
  }

  Future<bool> _isPatientVisibleToDoctor(String patientId,
      {bool preferCache = true}) async {
    if (!_isDoctorContext) return true;
    if (patientId.isEmpty) return true;
    return FirestoreService.instance.patientProfile
        .isPatientSharingClinicalDataWithDoctors(
      patientId,
      preferCache: preferCache,
    );
  }

  Future<List<PrescriptionDraft>> _filterPrescriptionsForDoctor(
    List<PrescriptionDraft> items, {
    bool preferCache = true,
  }) async {
    if (!_isDoctorContext) return items;

    final visible = <PrescriptionDraft>[];
    final decided = <String, bool>{};

    for (final draft in items) {
      final patientId = draft.patientId;
      if (patientId.isEmpty) {
        visible.add(draft);
        continue;
      }

      final cachedDecision = decided[patientId];
      if (cachedDecision == false) continue;
      if (cachedDecision == true) {
        visible.add(draft);
        continue;
      }

      final allowed =
          await _isPatientVisibleToDoctor(patientId, preferCache: preferCache);
      decided[patientId] = allowed;
      if (allowed) {
        visible.add(draft);
      } else {
        _purgePatientPrescriptions(patientId);
      }
    }

    return visible;
  }

  Future<void> save(PrescriptionDraft draft) async {
    // FIXED: now async + awaited so Firestore failures surface to the caller

    final copy = draft.copy();

    // Snapshot the prescribing doctor's details so patients can identify
    // who issued the prescription independent of their own session.
    final p = DoctorProfileStore.instance.profile;
    copy.doctorId = DoctorSession.loggedInDoctorId;
    copy.doctorName = DoctorProfileStore.displayNameWithPrefix;
    copy.doctorSpecialization = p.specialization;
    copy.doctorQualifications = p.qualification.trim().isNotEmpty
        ? p.qualification.trim()
        : (p.certifications.isNotEmpty
            ? p.certifications.join(', ')
            : [p.specialization, p.superSpecialization]
                .where((s) => s.trim().isNotEmpty)
                .join(' · '));
    copy.doctorRegNumber = p.councilNumber;
    copy.clinicName = p.clinicName;
    copy.doctorPhone = p.mobile;
    copy.clinicAddress = [p.addressLine1, p.addressLine2, p.city, p.pincode]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    final isNewRecord = findById(copy.prescriptionId) == null;

    await FirestoreService.instance.prescription.save(
      copy,
      DoctorSession.loggedInDoctorId,
      isNewRecord: isNewRecord,
    ); // FIXED: persist before updating local state; rethrows on failure

    _records.removeWhere((d) => d.prescriptionId == copy.prescriptionId);

    _records.insert(0, copy);

    notifyListeners();
  }

  void mergeFirestoreRecords(List<PrescriptionDraft> remoteRecords) {
    for (final remote in remoteRecords) {
      _records.removeWhere((d) => d.prescriptionId == remote.prescriptionId);

      _records.add(remote);
    }

    _records.sort((a, b) => b.prescriptionDate.compareTo(a.prescriptionDate));

    notifyListeners();
  }

  /// Applies sharing gate before merging doctor-facing Firestore payloads.
  Future<void> mergeFirestoreRecordsForDoctor(
    List<PrescriptionDraft> remoteRecords, {
    bool preferCache = true,
  }) async {
    final visible = await _filterPrescriptionsForDoctor(
      remoteRecords,
      preferCache: preferCache,
    );
    mergeFirestoreRecords(visible);
  }

  bool _hasDoctorRecords(String doctorId) =>
      doctorId.isNotEmpty && _records.any((r) => r.doctorId == doctorId);

  Future<void> refreshForDoctor({bool preferCache = true}) async {
    final doctorId = DoctorSession.loggedInDoctorId;
    if (preferCache && _hasDoctorRecords(doctorId)) return;

    _lastDoctorPage = null;

    _hasMoreDoctor = true;

    await loadMoreForDoctor(preferCache: preferCache);
  }

  Future<void> loadMoreForDoctor({bool preferCache = true}) async {
    if (!_hasMoreDoctor) return;

    final page = await FirestoreService.instance.prescription.fetchForDoctor(
      DoctorSession.loggedInDoctorId,
      startAfter: _lastDoctorPage,
      preferCache: preferCache,
    );

    final visible = await _filterPrescriptionsForDoctor(page.items,
        preferCache: preferCache);

    mergeFirestoreRecords(visible);

    _lastDoctorPage = page.lastDocument;

    _hasMoreDoctor = page.hasMore;
  }

  Future<void> refreshForPatient(String patientId,
      {bool preferCache = true}) async {
    if (_isDoctorContext &&
        !await _isPatientVisibleToDoctor(patientId, preferCache: preferCache)) {
      _purgePatientPrescriptions(patientId);
      _lastPatientPage = null;
      _hasMorePatient = false;
      return;
    }

    if (preferCache && _hasPatientRecords(patientId)) return;

    _lastPatientPage = null;

    _hasMorePatient = true;

    await loadMoreForPatient(patientId, preferCache: preferCache);
  }

  Future<void> loadMoreForPatient(String patientId,
      {bool preferCache = true}) async {
    if (!_hasMorePatient) return;

    if (_isDoctorContext &&
        !await _isPatientVisibleToDoctor(patientId, preferCache: preferCache)) {
      _purgePatientPrescriptions(patientId);
      _hasMorePatient = false;
      return;
    }

    // Patient reading prescriptions in Supabase-first mode:
    if (!_isDoctorContext && SupabaseBootstrap.isReady) {
      try {
        final rows = await SupabasePatientRepository.instance
            .fetchPrescriptions(patientId);
        final supaItems = rows
            .map((r) => PrescriptionSupabaseMapper.fromRow(r))
            .whereType<PrescriptionDraft>()
            .toList();
        if (supaItems.isNotEmpty) {
          mergeFirestoreRecords(supaItems);
          _hasMorePatient = false;
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'ClinicalPrescriptionStore: Supabase fetch failed, falling back to Firestore: $e');
        }
      }
    }

    try {
      final page = _isDoctorContext
          ? await FirestoreService.instance.prescription
              .fetchForPatientForDoctor(
              patientId,
              startAfter: _lastPatientPage,
              preferCache: preferCache,
            )
          : await FirestoreService.instance.prescription.fetchForPatient(
              patientId,
              startAfter: _lastPatientPage,
              preferCache: preferCache,
            );

      mergeFirestoreRecords(page.items);

      _lastPatientPage = page.lastDocument;

      _hasMorePatient = page.hasMore;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            'ClinicalPrescriptionStore.loadMoreForPatient failed: $e\n$st');
      }
      _hasMorePatient = false;
    }
  }
}
