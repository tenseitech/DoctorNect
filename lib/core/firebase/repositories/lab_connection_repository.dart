import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/lab/models/lab_connection_models.dart';
import '../../../features/pharmacy/models/pharmacy_models.dart';
import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_query_limits.dart';
import '../firestore_read_helper.dart';
import '../models/firestore_page.dart';

class LabConnectionRepository {
  LabConnectionRepository._();

  static final LabConnectionRepository instance = LabConnectionRepository._();

  Future<void> saveConnection(LabConnection connection) async {
    if (!FirebaseBootstrap.isReady) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.labConnections)
        .doc(connection.id)
        .set({
      'doctorId': connection.doctorId,
      'doctorName': connection.doctorName,
      'labId': connection.labId,
      'labName': connection.labName,
      'status': connection.status.name,
      'requestedBy': connection.requestedBy.name,
      'requestedAt': Timestamp.fromDate(connection.requestedAt),
      if (connection.respondedAt != null)
        'respondedAt': Timestamp.fromDate(connection.respondedAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<LabConnection>> watchPendingConnectionsForDoctor(
      String doctorId) {
    if (!FirebaseBootstrap.isReady) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection(FirestorePaths.labConnections)
        .where('doctorId', isEqualTo: doctorId)
        .where('status', isEqualTo: ConnectionStatus.pending.name)
        .limit(FirestoreQueryLimits.pendingConnections)
        .snapshots()
        .map(_mapConnectionSnapshot);
  }

  Stream<List<LabConnection>> watchPendingConnectionsForLab(String labId) {
    if (!FirebaseBootstrap.isReady) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection(FirestorePaths.labConnections)
        .where('labId', isEqualTo: labId)
        .where('status', isEqualTo: ConnectionStatus.pending.name)
        .limit(FirestoreQueryLimits.pendingConnections)
        .snapshots()
        .map(_mapConnectionSnapshot);
  }

  Future<FirestorePage<LabConnection>> fetchActiveConnectionsForDoctor(
    String doctorId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.connectionsPage,
    bool preferCache = true,
  }) {
    return _fetchConnections(
      doctorId: doctorId,
      status: ConnectionStatus.active,
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
    );
  }

  Future<FirestorePage<LabConnection>> fetchActiveConnectionsForLab(
    String labId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.connectionsPage,
    bool preferCache = true,
  }) {
    return _fetchConnections(
      labId: labId,
      status: ConnectionStatus.active,
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
    );
  }

  Future<FirestorePage<LabConnection>> _fetchConnections({
    String? doctorId,
    String? labId,
    required ConnectionStatus status,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    required int limit,
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return const FirestorePage(items: [], hasMore: false);
    }

    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection(FirestorePaths.labConnections);

    if (doctorId != null) {
      query = query.where('doctorId', isEqualTo: doctorId);
    } else if (labId != null) {
      query = query.where('labId', isEqualTo: labId);
    }

    query = query.where('status', isEqualTo: status.name).limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await FirestoreReadHelper.getQuery(
        query: query, preferCache: preferCache);
    final items = _mapConnectionDocs(snapshot.docs);

    return FirestorePage(
      items: items,
      lastDocument: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  List<LabConnection> _mapConnectionSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return _mapConnectionDocs(snapshot.docs);
  }

  List<LabConnection> _mapConnectionDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .map((doc) => _connectionFromMap(doc.id, doc.data()))
        .whereType<LabConnection>()
        .toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
  }

  LabConnection? _connectionFromMap(String id, Map<String, dynamic> data) {
    try {
      return LabConnection(
        id: id,
        doctorId: data['doctorId'] as String? ?? '',
        doctorName: data['doctorName'] as String? ?? '',
        labId: data['labId'] as String? ?? '',
        labName: data['labName'] as String? ?? '',
        status: ConnectionStatus.values
            .byName(data['status'] as String? ?? 'pending'),
        requestedBy: LabConnectionRequester.values.byName(
          data['requestedBy'] as String? ?? LabConnectionRequester.lab.name,
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
