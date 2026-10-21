import 'package:cloud_firestore/cloud_firestore.dart';

import '../../config/doctor_patient_cutover_flag.dart';
import '../../supabase/repositories/supabase_pharmacy_repository.dart';
import '../../../features/pharmacy/models/pharmacy_models.dart';
import '../firestore_paths.dart';
import '../firebase_bootstrap.dart';
import '../firestore_query_limits.dart';
import '../firestore_read_helper.dart';
import '../mappers/prescription_firestore_mapper.dart';
import '../models/firestore_page.dart';

class PharmacyFirestoreRepository {
  PharmacyFirestoreRepository._();

  static final PharmacyFirestoreRepository instance =
      PharmacyFirestoreRepository._();

  Future<void> saveConnection(PharmacyConnection connection) async {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance.saveConnection(connection);
    }
    if (!FirebaseBootstrap.isReady) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.pharmacyConnections)
        .doc(connection.id)
        .set({
      'doctorId': connection.doctorId,
      'doctorName': connection.doctorName,
      'medicalStoreId': connection.medicalStoreId,
      'storeName': connection.storeName,
      'status': connection.status.name,
      'requestedBy': connection.requestedBy.name,
      'requestedAt': Timestamp.fromDate(connection.requestedAt),
      if (connection.respondedAt != null)
        'respondedAt': Timestamp.fromDate(connection.respondedAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveDelivery(PharmacyPrescriptionDelivery delivery) async {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance.saveDelivery(delivery);
    }
    if (!FirebaseBootstrap.isReady) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.pharmacyDeliveries)
        .doc(delivery.id)
        .set({
      'prescriptionId': delivery.prescriptionId,
      'doctorId': delivery.doctorId,
      'doctorName': delivery.doctorName,
      'storeId': delivery.storeId,
      'storeName': delivery.storeName,
      'patientId': delivery.draft.patientId,
      'patientName': delivery.draft.patient.patientName,
      'status': delivery.status.name,
      'sentAt': Timestamp.fromDate(delivery.sentAt),
      if (delivery.viewedAt != null)
        'viewedAt': Timestamp.fromDate(delivery.viewedAt!),
      if (delivery.dispensedAt != null)
        'dispensedAt': Timestamp.fromDate(delivery.dispensedAt!),
      if (delivery.dispensingNotes.isNotEmpty)
        'dispensingNotes': delivery.dispensingNotes,
      'medicineCount': delivery.medicineLines.length,
      'medicineLines': _medicineLinesToMap(
        delivery.medicineLines,
      ), // FIXED: persist per-medicine availability/substitute
      'draft': PrescriptionFirestoreMapper.toMap(
        delivery.draft,
        delivery.doctorId,
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateDelivery(PharmacyPrescriptionDelivery delivery) async {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance.updateDelivery(delivery);
    }
    if (!FirebaseBootstrap.isReady) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.pharmacyDeliveries)
        .doc(delivery.id)
        .set({
      'status': delivery.status.name,
      if (delivery.viewedAt != null)
        'viewedAt': Timestamp.fromDate(delivery.viewedAt!),
      if (delivery.dispensedAt != null)
        'dispensedAt': Timestamp.fromDate(delivery.dispensedAt!),
      'dispensingNotes': delivery.dispensingNotes,
      'medicineLines': _medicineLinesToMap(
        delivery.medicineLines,
      ), // FIXED: persist per-medicine availability/substitute
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // FIXED: serialize dispense-line state so OOS/substitute choices survive a reload
  List<Map<String, dynamic>> _medicineLinesToMap(
    List<MedicineDispenseLine> lines,
  ) {
    return lines
        .map(
          (l) => {
            'medicineEntryId': l.medicineEntryId,
            'availability': l.availability.name,
            'substituteName': l.substituteName,
          },
        )
        .toList();
  }

  // FIXED: restore availability and substituteName into pre-built lines
  void _applyStoredMedicineLines(
    List<MedicineDispenseLine> lines,
    dynamic rawStoredLines,
  ) {
    if (rawStoredLines is! List) return;
    final map = <String, Map<String, dynamic>>{};
    for (final item in rawStoredLines) {
      if (item is Map) {
        final entryId = item['medicineEntryId'] as String?;
        if (entryId != null) {
          map[entryId] = Map<String, dynamic>.from(item);
        }
      }
    }
    for (final line in lines) {
      final stored = map[line.medicineEntryId];
      if (stored != null) {
        final availStr = stored['availability'] as String?;
        if (availStr != null) {
          try {
            line.availability = MedicineAvailability.values.byName(availStr);
          } catch (_) {}
        }
        line.substituteName = stored['substituteName'] as String? ?? '';
      }
    }
  }

  Future<PharmacyPrescriptionDelivery?> fetchDeliveryById(
    String deliveryId, {
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady || deliveryId.isEmpty) return null;

    final doc = await FirestoreReadHelper.getDocument(
      reference: FirebaseFirestore.instance
          .collection(FirestorePaths.pharmacyDeliveries)
          .doc(deliveryId),
      preferCache: preferCache,
    );

    final data = doc.data();
    if (data == null) return null;
    return _deliveryFromMap(doc.id, data);
  }

  Future<PharmacyPrescriptionDelivery?> fetchDeliveryByPrescriptionId(
    String prescriptionId, {
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady || prescriptionId.isEmpty) return null;

    final snapshot = await FirestoreReadHelper.getQuery(
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.pharmacyDeliveries)
          .where('prescriptionId', isEqualTo: prescriptionId)
          .limit(1),
      preferCache: preferCache,
    );

    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return _deliveryFromMap(doc.id, doc.data());
  }

  Future<List<PharmacyPrescriptionDelivery>> fetchDeliveriesForPatient(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance
          .fetchDeliveriesForPatient(patientId);
    }
    if (!FirebaseBootstrap.isReady || patientId.isEmpty) return const [];

    final snapshot = await FirestoreReadHelper.getQuery(
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.pharmacyDeliveries)
          .where('patientId', isEqualTo: patientId)
          .orderBy('sentAt', descending: true)
          .limit(FirestoreQueryLimits.connectionsPage),
      preferCache: preferCache,
    );

    return snapshot.docs
        .map((doc) => _deliveryFromMap(doc.id, doc.data()))
        .whereType<PharmacyPrescriptionDelivery>()
        .toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
  }

  Future<List<PharmacyPrescriptionDelivery>> fetchDeliveriesForDoctor(
    String doctorId, {
    bool preferCache = true,
  }) async {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance
          .fetchDeliveriesForDoctor(doctorId);
    }
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) return const [];

    final snapshot = await FirestoreReadHelper.getQuery(
      query: FirebaseFirestore.instance
          .collection(FirestorePaths.pharmacyDeliveries)
          .where('doctorId', isEqualTo: doctorId)
          .orderBy('sentAt', descending: true)
          .limit(FirestoreQueryLimits.connectionsPage),
      preferCache: preferCache,
    );

    return snapshot.docs
        .map((doc) => _deliveryFromMap(doc.id, doc.data()))
        .whereType<PharmacyPrescriptionDelivery>()
        .toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
  }

  /// Real-time listener for a store's incoming deliveries.
  Stream<List<PharmacyPrescriptionDelivery>> watchDeliveriesForStore(
    String storeId,
  ) {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance
          .watchDeliveriesForStore(storeId);
    }
    if (!FirebaseBootstrap.isReady) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection(FirestorePaths.pharmacyDeliveries)
        .where('storeId', isEqualTo: storeId)
        .limit(FirestoreQueryLimits.connectionsPage)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => _deliveryFromMap(doc.id, doc.data()))
              .whereType<PharmacyPrescriptionDelivery>()
              .toList()
            ..sort((a, b) => b.sentAt.compareTo(a.sentAt)),
        );
  }

  Stream<List<PharmacyPrescriptionDelivery>> watchDeliveriesForDoctor(
    String doctorId,
  ) {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance
          .watchDeliveriesForDoctor(doctorId);
    }
    if (!FirebaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }
    return FirebaseFirestore.instance
        .collection(FirestorePaths.pharmacyDeliveries)
        .where('doctorId', isEqualTo: doctorId)
        .orderBy('sentAt', descending: true)
        .limit(FirestoreQueryLimits.connectionsPage)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => _deliveryFromMap(doc.id, doc.data()))
              .whereType<PharmacyPrescriptionDelivery>()
              .toList()
            ..sort((a, b) => b.sentAt.compareTo(a.sentAt)),
        );
  }

  PharmacyPrescriptionDelivery? _deliveryFromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    try {
      final draftMap = data['draft'] as Map<String, dynamic>?;
      if (draftMap == null) return null;
      final draft = PrescriptionFirestoreMapper.fromMap(draftMap);
      if (draft == null) return null;

      final lines = PharmacyPrescriptionDelivery.linesFromDraft(draft);
      _applyStoredMedicineLines(lines, data['medicineLines']);

      return PharmacyPrescriptionDelivery(
        id: id,
        prescriptionId:
            data['prescriptionId'] as String? ?? draft.prescriptionId,
        doctorId: data['doctorId'] as String? ?? '',
        doctorName: data['doctorName'] as String? ?? '',
        storeId: data['storeId'] as String? ?? '',
        storeName: data['storeName'] as String? ?? '',
        draft: draft,
        sentAt: (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        status: PharmacyDeliveryStatus.values.byName(
          data['status'] as String? ?? 'sent',
        ),
        viewedAt: (data['viewedAt'] as Timestamp?)?.toDate(),
        dispensedAt: (data['dispensedAt'] as Timestamp?)?.toDate(),
        dispensingNotes: data['dispensingNotes'] as String? ?? '',
        medicineLines: lines,
      );
    } catch (_) {
      return null;
    }
  }

  /// Real-time listener for pending requests only (narrow query + limit).
  Stream<List<PharmacyConnection>> watchPendingConnectionsForDoctor(
    String doctorId,
  ) {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance
          .watchPendingConnectionsForDoctor(doctorId);
    }
    if (!FirebaseBootstrap.isReady) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection(FirestorePaths.pharmacyConnections)
        .where('doctorId', isEqualTo: doctorId)
        .where('status', isEqualTo: ConnectionStatus.pending.name)
        .limit(FirestoreQueryLimits.pendingConnections)
        .snapshots()
        .map(_mapConnectionSnapshot);
  }

  /// Real-time listener for pending requests only (narrow query + limit).
  Stream<List<PharmacyConnection>> watchPendingConnectionsForStore(
    String storeId,
  ) {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance
          .watchPendingConnectionsForStore(storeId);
    }
    if (!FirebaseBootstrap.isReady) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection(FirestorePaths.pharmacyConnections)
        .where('medicalStoreId', isEqualTo: storeId)
        .where('status', isEqualTo: ConnectionStatus.pending.name)
        .limit(FirestoreQueryLimits.pendingConnections)
        .snapshots()
        .map(_mapConnectionSnapshot);
  }

  /// One-time fetch for active connections (cache-first).
  Future<FirestorePage<PharmacyConnection>> fetchActiveConnectionsForDoctor(
    String doctorId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.connectionsPage,
    bool preferCache = true,
  }) {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance
          .fetchActiveConnectionsForDoctor(doctorId, limit: limit);
    }
    return _fetchConnections(
      doctorId: doctorId,
      status: ConnectionStatus.active,
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
    );
  }

  /// One-time fetch for active connections (cache-first).
  Future<FirestorePage<PharmacyConnection>> fetchActiveConnectionsForStore(
    String storeId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.connectionsPage,
    bool preferCache = true,
  }) {
    if (DoctorPatientCutoverFlag.isEnabled) {
      return SupabasePharmacyRepository.instance
          .fetchActiveConnectionsForStore(storeId, limit: limit);
    }
    return _fetchConnections(
      storeId: storeId,
      status: ConnectionStatus.active,
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
    );
  }

  Future<FirestorePage<PharmacyConnection>> _fetchConnections({
    String? doctorId,
    String? storeId,
    required ConnectionStatus status,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    required int limit,
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return const FirestorePage(items: [], hasMore: false);
    }

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      FirestorePaths.pharmacyConnections,
    );

    if (doctorId != null) {
      query = query.where('doctorId', isEqualTo: doctorId);
    } else if (storeId != null) {
      query = query.where('medicalStoreId', isEqualTo: storeId);
    }

    query = query.where('status', isEqualTo: status.name).limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await FirestoreReadHelper.getQuery(
      query: query,
      preferCache: preferCache,
    );
    final items = _mapConnectionDocs(snapshot.docs);

    return FirestorePage(
      items: items,
      lastDocument: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  List<PharmacyConnection> _mapConnectionSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return _mapConnectionDocs(snapshot.docs);
  }

  List<PharmacyConnection> _mapConnectionDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .map((doc) => _connectionFromMap(doc.id, doc.data()))
        .whereType<PharmacyConnection>()
        .toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
  }

  PharmacyConnection? _connectionFromMap(String id, Map<String, dynamic> data) {
    try {
      return PharmacyConnection(
        id: id,
        doctorId: data['doctorId'] as String? ?? '',
        doctorName: data['doctorName'] as String? ?? '',
        medicalStoreId: data['medicalStoreId'] as String? ?? '',
        storeName: data['storeName'] as String? ?? '',
        status: ConnectionStatus.values.byName(
          data['status'] as String? ?? 'pending',
        ),
        requestedBy: ConnectionRequester.values.byName(
          data['requestedBy'] as String? ?? ConnectionRequester.store.name,
        ),
        requestedAt:
            (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
      );
    } catch (_) {
      return null;
    }
  }
}
