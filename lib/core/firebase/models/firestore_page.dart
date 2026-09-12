import 'package:cloud_firestore/cloud_firestore.dart';

class FirestorePage<T> {
  const FirestorePage({
    required this.items,
    this.lastDocument,
    required this.hasMore,
  });

  final List<T> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}
