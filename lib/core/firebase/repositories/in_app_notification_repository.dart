import 'package:cloud_firestore/cloud_firestore.dart';

import '../../notifications/app_notification.dart';
import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_query_limits.dart';
import '../mappers/in_app_notification_firestore_mapper.dart';

class InAppNotificationRepository {
  InAppNotificationRepository._();

  static final InAppNotificationRepository instance =
      InAppNotificationRepository._();

  Stream<List<AppNotification>> watchForRecipient(String recipientUid) {
    if (!FirebaseBootstrap.isReady || recipientUid.isEmpty) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection(FirestorePaths.inAppNotifications)
        .where('recipientUid', isEqualTo: recipientUid)
        .orderBy('createdAt', descending: true)
        .limit(FirestoreQueryLimits.inAppNotifications)
        .snapshots()
        .map(_notificationsFromSnapshot);
  }

  Future<void> markRead(String notificationDocId) async {
    if (!FirebaseBootstrap.isReady || notificationDocId.isEmpty) return;

    await FirebaseFirestore.instance
        .collection(FirestorePaths.inAppNotifications)
        .doc(notificationDocId)
        .update({'isRead': true});
  }

  Future<void> markAllRead(Iterable<String> notificationDocIds) async {
    if (!FirebaseBootstrap.isReady) return;

    final ids = notificationDocIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    final collection = FirebaseFirestore.instance
        .collection(FirestorePaths.inAppNotifications);
    for (final id in ids) {
      batch.update(collection.doc(id), {'isRead': true});
    }
    await batch.commit();
  }

  List<AppNotification> _notificationsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs
        .map((doc) =>
            InAppNotificationFirestoreMapper.fromMap(doc.id, doc.data()))
        .whereType<AppNotification>()
        .toList();
  }
}
