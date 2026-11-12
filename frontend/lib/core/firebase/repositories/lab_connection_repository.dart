import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/lab/models/lab_connection_models.dart';
import '../../supabase/repositories/supabase_lab_repository.dart';
import '../firestore_query_limits.dart';
import '../models/firestore_page.dart';

class LabConnectionRepository {
  LabConnectionRepository._();

  static final LabConnectionRepository instance = LabConnectionRepository._();

  Future<void> saveConnection(LabConnection connection) async {
    return SupabaseLabRepository.instance.saveConnection(connection);
  }

  Stream<List<LabConnection>> watchPendingConnectionsForDoctor(
    String doctorId,
  ) {
    return SupabaseLabRepository.instance
        .watchPendingConnectionsForDoctor(doctorId);
  }

  Stream<List<LabConnection>> watchPendingConnectionsForLab(String labId) {
    return SupabaseLabRepository.instance.watchPendingConnectionsForLab(labId);
  }

  Future<FirestorePage<LabConnection>> fetchActiveConnectionsForDoctor(
    String doctorId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.connectionsPage,
    bool preferCache = true,
  }) {
    return SupabaseLabRepository.instance.fetchActiveConnectionsForDoctor(
      doctorId,
      limit: limit,
    );
  }

  Future<FirestorePage<LabConnection>> fetchActiveConnectionsForLab(
    String labId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.connectionsPage,
    bool preferCache = true,
  }) {
    return SupabaseLabRepository.instance.fetchActiveConnectionsForLab(
      labId,
      limit: limit,
    );
  }
}
