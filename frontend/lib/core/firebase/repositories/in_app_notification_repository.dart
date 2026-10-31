import '../../notifications/app_notification.dart';
import '../../supabase/in_app_notification_supabase_repository.dart';

class InAppNotificationRepository {
  InAppNotificationRepository._();

  static final InAppNotificationRepository instance =
      InAppNotificationRepository._();

  Stream<List<AppNotification>> watchForRecipient(String recipientUid) {
    return InAppNotificationSupabaseRepository.instance
        .watchForRecipient(recipientUid);
  }

  Future<void> markRead(String notificationDocId) async {
    await InAppNotificationSupabaseRepository.instance
        .markRead(notificationDocId);
  }

  Future<void> markAllRead(Iterable<String> notificationDocIds) async {
    await InAppNotificationSupabaseRepository.instance
        .markAllRead(notificationDocIds);
  }
}
