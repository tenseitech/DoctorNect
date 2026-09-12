import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/foundation.dart';

import '../../doctor/clinical/models/clinical_models.dart';
import '../models/pharmacy_models.dart';
import 'medical_store_registry.dart';
import 'pharmacy_connection_store.dart';
import 'pharmacy_notification_store.dart';

class PharmacyPrescriptionStore extends ChangeNotifier {
  PharmacyPrescriptionStore._();

  static final PharmacyPrescriptionStore instance = PharmacyPrescriptionStore._();

  final List<PharmacyPrescriptionDelivery> _deliveries = [];

  List<PharmacyPrescriptionDelivery> get all => List.unmodifiable(_deliveries);

  void clear() {
    _deliveries.clear();
    notifyListeners();
  }

  List<PharmacyPrescriptionDelivery> forStore(String storeId) =>
      _deliveries.where((d) => d.storeId == storeId).toList()
        ..sort((a, b) => b.sentAt.compareTo(a.sentAt));

  List<PharmacyPrescriptionDelivery> forDoctor(String doctorId) =>
      _deliveries.where((d) => d.doctorId == doctorId).toList()
        ..sort((a, b) => b.sentAt.compareTo(a.sentAt));

  List<PharmacyPrescriptionDelivery> forPatient(String patientId) =>
      _deliveries.where((d) => d.draft.patientId == patientId).toList()
        ..sort((a, b) => b.sentAt.compareTo(a.sentAt));

  List<PharmacyPrescriptionDelivery> forPrescription({
    required String prescriptionId,
    String? patientId,
  }) {
    return _deliveries.where((d) {
      if (d.prescriptionId != prescriptionId) return false;
      if (patientId != null && patientId.isNotEmpty && d.draft.patientId != patientId) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
  }

  Future<void> refreshForPatient(String patientId, {bool preferCache = true}) async {
    if (patientId.isEmpty) return;
    final remote = await FirestoreService.instance.pharmacyFirestore.fetchDeliveriesForPatient(
      patientId,
      preferCache: preferCache,
    );
    mergeFromFirestore(remote);
  }

  Future<void> refreshForDoctor(String doctorId, {bool preferCache = true}) async {
    if (doctorId.isEmpty) return;
    if (preferCache && forDoctor(doctorId).isNotEmpty) return;

    final remote = await FirestoreService.instance.pharmacyFirestore.fetchDeliveriesForDoctor(
      doctorId,
      preferCache: preferCache,
    );
    mergeFromFirestore(remote);
  }

  List<PharmacyPrescriptionDelivery> forStoreAndDoctor(String storeId, String doctorId) =>
      _deliveries
          .where((d) => d.storeId == storeId && d.doctorId == doctorId)
          .toList()
        ..sort((a, b) => b.sentAt.compareTo(a.sentAt));

  Map<String, List<PharmacyPrescriptionDelivery>> groupedByDoctorForStore(String storeId) {
    final map = <String, List<PharmacyPrescriptionDelivery>>{};
    for (final d in forStore(storeId)) {
      map.putIfAbsent(d.doctorId, () => []).add(d);
    }
    return map;
  }

  int unreadCountForStoreDoctor(String storeId, String doctorId) =>
      forStoreAndDoctor(storeId, doctorId)
          .where((d) => d.status == PharmacyDeliveryStatus.sent)
          .length;

  PharmacyPrescriptionDelivery? findById(String id) {
    for (final d in _deliveries) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<List<PharmacyPrescriptionDelivery>> sendToStores({ // FIXED: async so Firestore writes are awaited and failures surface
    required PrescriptionDraft draft,
    required List<String> storeIds,
    required String doctorId,
    required String doctorName,
  }) async {
    final connectedIds = storeIds
        .where((id) => PharmacyConnectionStore.instance.isConnected(doctorId, id))
        .toList();

    final created = <PharmacyPrescriptionDelivery>[];
    for (final storeId in connectedIds) {
      await MedicalStoreRegistry.ensureStoreLoaded(storeId);
      final store = MedicalStoreRegistry.findById(storeId);
      final connection = PharmacyConnectionStore.instance
          .activeForDoctor(doctorId)
          .where((c) => c.medicalStoreId == storeId)
          .firstOrNull;
      final storeName = store?.storeName ?? connection?.storeName ?? '';
      if (storeName.isEmpty) continue;

      final delivery = PharmacyPrescriptionDelivery(
        id: 'rxdel-${DateTime.now().microsecondsSinceEpoch}-$storeId',
        prescriptionId: draft.prescriptionId,
        doctorId: doctorId,
        doctorName: doctorName,
        storeId: storeId,
        storeName: storeName,
        draft: draft.copyForPharmacy(),
        sentAt: DateTime.now(),
        medicineLines: PharmacyPrescriptionDelivery.linesFromDraft(draft),
      );
      await FirestoreService.instance.pharmacyFirestore.saveDelivery(delivery); // FIXED: await; rethrows on failure
      _deliveries.insert(0, delivery);
      created.add(delivery);

      PharmacyNotificationStore.instance.addStore(
        storeId: storeId,
        title: 'New prescription',
        message: 'New prescription from Dr. $doctorName — ${draft.patient.patientName}',
        referenceId: delivery.id,
      );
    }

    if (connectedIds.isNotEmpty && created.isEmpty) {
      throw StateError('Could not send to the selected medical store(s). Please try again.');
    }

    if (created.isNotEmpty) notifyListeners();
    return created;
  }

  Future<void> markViewed(String deliveryId) async { // FIXED: async + awaited write
    final d = findById(deliveryId);
    if (d == null || d.status != PharmacyDeliveryStatus.sent) return;
    d.status = PharmacyDeliveryStatus.viewed;
    d.viewedAt = DateTime.now();

    await FirestoreService.instance.pharmacyFirestore.updateDelivery(d); // FIXED: await; rethrows on failure
    notifyListeners();
  }

  Future<void> updateMedicineLine({ // FIXED: async so per-medicine availability is persisted to Firestore
    required String deliveryId,
    required String medicineEntryId,
    required MedicineAvailability availability,
    String substituteName = '',
  }) async {
    final d = findById(deliveryId);
    if (d == null) return;
    for (final line in d.medicineLines) {
      if (line.medicineEntryId == medicineEntryId) {
        line.availability = availability;
        line.substituteName = substituteName;
        break;
      }
    }
    await FirestoreService.instance.pharmacyFirestore.updateDelivery(d); // FIXED: persist medicineLines availability/substitute to Firestore
    notifyListeners();
  }

  Future<void> markDispensed(String deliveryId, {required String notes}) async { // FIXED: async + awaited write
    final d = findById(deliveryId);
    if (d == null) return;

    final hasPartial = d.medicineLines.any(
      (l) =>
          l.availability == MedicineAvailability.outOfStock ||
          l.availability == MedicineAvailability.substituted,
    );
    d.status = hasPartial ? PharmacyDeliveryStatus.partiallyDispensed : PharmacyDeliveryStatus.dispensed;
    d.dispensedAt = DateTime.now();
    d.dispensingNotes = notes;

    await FirestoreService.instance.pharmacyFirestore.updateDelivery(d); // FIXED: await; rethrows on failure

    notifyListeners();
  }

  void mergeFromFirestore(List<PharmacyPrescriptionDelivery> remoteDeliveries) {
    for (final remote in remoteDeliveries) {
      _deliveries.removeWhere((d) => d.id == remote.id);
      _deliveries.insert(0, remote);
    }
    notifyListeners();
  }
}
