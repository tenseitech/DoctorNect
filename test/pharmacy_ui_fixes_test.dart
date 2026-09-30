import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/pharmacy/data/pharmacy_notification_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PharmacyNotificationStore New vs Read partitioning', () {
    const storeId = 'store-test-123';

    setUp(() {
      PharmacyNotificationStore.instance.clear();
    });

    test('addStore creates unread notification in New partition', () {
      PharmacyNotificationStore.instance.addStore(
        storeId: storeId,
        title: 'New prescription received',
        message: 'Dr. Smith sent a prescription for John Doe',
        referenceId: 'del-101',
      );

      final all = PharmacyNotificationStore.instance.forStore(storeId);
      expect(all.length, 1);
      expect(all.first.isRead, isFalse);

      final unread = all.where((n) => !n.isRead).toList();
      final read = all.where((n) => n.isRead).toList();

      expect(unread.length, 1);
      expect(read.length, 0);
      expect(
          PharmacyNotificationStore.instance.unreadCountForStore(storeId), 1);
    });

    test('markRead moves notification from New to Read', () {
      PharmacyNotificationStore.instance.addStore(
        storeId: storeId,
        title: 'New prescription received',
        message: 'Dr. Smith sent a prescription for John Doe',
        referenceId: 'del-101',
      );

      final notifId =
          PharmacyNotificationStore.instance.forStore(storeId).first.id;
      PharmacyNotificationStore.instance.markRead(notifId);

      final all = PharmacyNotificationStore.instance.forStore(storeId);
      final unread = all.where((n) => !n.isRead).toList();
      final read = all.where((n) => n.isRead).toList();

      expect(unread.length, 0);
      expect(read.length, 1);
      expect(read.first.id, notifId);
      expect(
          PharmacyNotificationStore.instance.unreadCountForStore(storeId), 0);
    });

    test('markAllReadForStore moves all notifications from New to Read', () {
      PharmacyNotificationStore.instance.addStore(
        storeId: storeId,
        title: 'Notification 1',
        message: 'Message 1',
      );
      PharmacyNotificationStore.instance.addStore(
        storeId: storeId,
        title: 'Notification 2',
        message: 'Message 2',
      );

      expect(
          PharmacyNotificationStore.instance.unreadCountForStore(storeId), 2);

      PharmacyNotificationStore.instance.markAllReadForStore(storeId);

      final all = PharmacyNotificationStore.instance.forStore(storeId);
      final unread = all.where((n) => !n.isRead).toList();
      final read = all.where((n) => n.isRead).toList();

      expect(unread.length, 0);
      expect(read.length, 2);
      expect(
          PharmacyNotificationStore.instance.unreadCountForStore(storeId), 0);
    });
  });

  group('Pharmacy prescription date range matching logic', () {
    bool isDateInRange(DateTime target, DateTime start, DateTime end) {
      final t = DateTime(target.year, target.month, target.day);
      final s = DateTime(start.year, start.month, start.day);
      final e = DateTime(end.year, end.month, end.day);
      return (t.isAtSameMomentAs(s) || t.isAfter(s)) &&
          (t.isAtSameMomentAs(e) || t.isBefore(e));
    }

    test('correctly matches date within range', () {
      final start = DateTime(2026, 7, 12);
      final end = DateTime(2026, 7, 16);

      expect(isDateInRange(DateTime(2026, 7, 12), start, end), isTrue);
      expect(isDateInRange(DateTime(2026, 7, 14, 15, 30), start, end), isTrue);
      expect(isDateInRange(DateTime(2026, 7, 16, 23, 59), start, end), isTrue);
      expect(isDateInRange(DateTime(2026, 7, 11), start, end), isFalse);
      expect(isDateInRange(DateTime(2026, 7, 17), start, end), isFalse);
    });

    test('single day range correctly matches only that day', () {
      final day = DateTime(2026, 7, 12);
      expect(isDateInRange(DateTime(2026, 7, 12, 9, 0), day, day), isTrue);
      expect(isDateInRange(DateTime(2026, 7, 13), day, day), isFalse);
    });
  });
}
