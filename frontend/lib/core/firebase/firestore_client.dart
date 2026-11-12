import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/firestore_forbidden_guard.dart';

/// Single entry for raw [FirebaseFirestore.instance] outside repository layer.
abstract final class FirestoreClient {
  static FirebaseFirestore get instance {
    FirestoreForbiddenGuard.assertNotForbidden('FirebaseFirestore.instance');
    return FirebaseFirestore.instance;
  }
}
