import 'package:cloud_firestore/cloud_firestore.dart';

import '../../supabase/repositories/supabase_pharmacy_repository.dart';
import '../../../features/pharmacy/models/pharmacy_models.dart';
import '../firestore_query_limits.dart';
import '../models/firestore_page.dart';

class PharmacyFirestoreRepository {
  PharmacyFirestoreRepository._();

  static final PharmacyFirestoreRepository instance =
      PharmacyFirestoreRepository._();

  Future<void> saveConnection(PharmacyConnection connection) async {
    return SupabasePharmacyRepository.instance.saveConnection(connection);
  }

  Future<void> saveDelivery(PharmacyPrescriptionDelivery delivery) async {
    return SupabasePharmacyRepository.instance.saveDelivery(delivery);
  }

  Future<void> updateDelivery(PharmacyPrescriptionDelivery delivery) async {
    return SupabasePharmacyRepository.instance.updateDelivery(delivery);
  }

  Future<PharmacyPrescriptionDelivery?> fetchDeliveryById(
    String deliveryId, {
    bool preferCache = true,
  }) async {
    return SupabasePharmacyRepository.instance.fetchDeliveryById(deliveryId);
  }

  Future<PharmacyPrescriptionDelivery?> fetchDeliveryByPrescriptionId(
    String prescriptionId, {
    bool preferCache = true,
  }) async {
    return SupabasePharmacyRepository.instance
        .fetchDeliveryByPrescriptionId(prescriptionId);
  }

  Future<List<PharmacyPrescriptionDelivery>> fetchDeliveriesForPatient(
    String patientId, {
    bool preferCache = true,
  }) async {
    return SupabasePharmacyRepository.instance
        .fetchDeliveriesForPatient(patientId);
  }

  Future<List<PharmacyPrescriptionDelivery>> fetchDeliveriesForDoctor(
    String doctorId, {
    bool preferCache = true,
  }) async {
    return SupabasePharmacyRepository.instance.fetchDeliveriesForDoctor(doctorId);
  }

  Future<List<PharmacyPrescriptionDelivery>> fetchDeliveriesForStore(
    String storeId, {
    bool preferCache = true,
  }) async {
    return SupabasePharmacyRepository.instance.fetchDeliveriesForStore(storeId);
  }

  Stream<List<PharmacyPrescriptionDelivery>> watchDeliveriesForStore(
    String storeId,
  ) {
    return SupabasePharmacyRepository.instance.watchDeliveriesForStore(storeId);
  }

  Stream<List<PharmacyPrescriptionDelivery>> watchDeliveriesForDoctor(
    String doctorId,
  ) {
    return SupabasePharmacyRepository.instance.watchDeliveriesForDoctor(doctorId);
  }

  Stream<List<PharmacyConnection>> watchPendingConnectionsForDoctor(
    String doctorId,
  ) {
    return SupabasePharmacyRepository.instance
        .watchPendingConnectionsForDoctor(doctorId);
  }

  Stream<List<PharmacyConnection>> watchPendingConnectionsForStore(
    String storeId,
  ) {
    return SupabasePharmacyRepository.instance
        .watchPendingConnectionsForStore(storeId);
  }

  Future<FirestorePage<PharmacyConnection>> fetchActiveConnectionsForDoctor(
    String doctorId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.connectionsPage,
    bool preferCache = true,
  }) {
    return SupabasePharmacyRepository.instance
        .fetchActiveConnectionsForDoctor(doctorId, limit: limit);
  }

  Future<FirestorePage<PharmacyConnection>> fetchActiveConnectionsForStore(
    String storeId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.connectionsPage,
    bool preferCache = true,
  }) {
    return SupabasePharmacyRepository.instance
        .fetchActiveConnectionsForStore(storeId, limit: limit);
  }
}
