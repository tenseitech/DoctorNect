import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:medibond/core/notifications/app_notification.dart';
import 'package:medibond/core/notifications/patient_notification_trigger.dart';
import 'package:medibond/core/supabase/in_app_notification_supabase_repository.dart';
import 'package:medibond/core/supabase/support_ticket_supabase_repository.dart';
import 'package:medibond/core/supabase/supabase_watcher_state_machine.dart';

void main() {
  group('Phase E: Support Ticket & Message Models Mapping', () {
    test('SupportTicketModel fromJson and toJson roundtrip', () {
      final json = {
        'ticket_id': 'tkt_123',
        'subject': 'Billing issue',
        'status': 'open',
        'priority': 'high',
        'patient_id': 'pat_456',
        'category': 'billing',
        'created_at': '2026-10-21T10:00:00.000Z',
        'updated_at': '2026-10-21T10:30:00.000Z',
      };

      final model = SupportTicketModel.fromJson(json);
      expect(model.ticketId, 'tkt_123');
      expect(model.subject, 'Billing issue');
      expect(model.status, 'open');
      expect(model.priority, 'high');
      expect(model.patientId, 'pat_456');
      expect(model.category, 'billing');
      expect(model.createdAt, isNotNull);

      final outJson = model.toJson();
      expect(outJson['ticket_id'], 'tkt_123');
      expect(outJson['subject'], 'Billing issue');
      expect(outJson['priority'], 'high');
    });

    test('TicketMessageModel fromJson and toJson roundtrip', () {
      final json = {
        'message_id': 'msg_789',
        'ticket_id': 'tkt_123',
        'sender_id': 'pat_456',
        'sender_role': 'patient',
        'message_text': 'I have a question about the invoice.',
        'created_at': '2026-10-21T10:05:00.000Z',
      };

      final msg = TicketMessageModel.fromJson(json);
      expect(msg.messageId, 'msg_789');
      expect(msg.ticketId, 'tkt_123');
      expect(msg.senderRole, 'patient');
      expect(msg.messageText, 'I have a question about the invoice.');

      final outJson = msg.toJson();
      expect(outJson['message_id'], 'msg_789');
      expect(outJson['message_text'], 'I have a question about the invoice.');
    });
  });

  group('Phase E: In-App Notification Supabase Mapping', () {
    test('notificationFromRow maps DB columns to AppNotification', () {
      final row = {
        'notification_id': 'notif_abc',
        'recipient_uid': 'fb_user_1',
        'title': 'Appointment Confirmed',
        'body': 'Your appointment with Dr. Alpha is confirmed.',
        'patient_trigger': 'bookingConfirmed',
        'type': 'appointment',
        'is_read': false,
        'created_at': '2026-10-21T08:00:00.000Z',
        'dedupe_key': 'appt_confirmed_123',
      };

      final notif = InAppNotificationSupabaseRepository.notificationFromRow(row);
      expect(notif, isNotNull);
      expect(notif!.id, 'notif_abc');
      expect(notif.title, 'Appointment Confirmed');
      expect(notif.body, 'Your appointment with Dr. Alpha is confirmed.');
      expect(notif.type, AppNotificationType.appointment);
      expect(notif.isRead, false);
      expect(notif.patientTrigger, PatientNotificationTrigger.bookingConfirmed);
      expect(notif.dedupeKey, 'appt_confirmed_123');
    });

    test('notificationFromRow returns null on missing required title/body', () {
      final row = {
        'notification_id': 'notif_bad',
        'title': '',
        'body': '',
      };
      final notif = InAppNotificationSupabaseRepository.notificationFromRow(row);
      expect(notif, isNull);
    });
  });

  group('Phase E: SupabaseWatcherStateMachine for Tickets & Notifications', () {
    test('State machine error surfacing and cache resync', () async {
      var shouldFail = true;
      final items = [
        const SupportTicketModel(
          ticketId: 'tkt_1',
          subject: 'First ticket',
          status: 'open',
          priority: 'normal',
        ),
      ];

      final watcher = SupabaseWatcherStateMachine<SupportTicketModel>(
        fetcher: () async {
          if (shouldFail) throw Exception('Simulated network error');
          return items;
        },
        getId: (t) => t.ticketId,
      );

      final errors = <Object>[];
      final values = <List<SupportTicketModel>>[];
      final sub = watcher.stream().listen(
        values.add,
        onError: errors.add,
      );

      await pumpEventQueue();
      expect(errors.length, 1);
      expect(errors.first, isA<Exception>());

      // Now heal fetcher and resync
      shouldFail = false;
      await watcher.resync();
      await pumpEventQueue();

      expect(watcher.cachedList.length, 1);
      expect(watcher.cachedList.first.ticketId, 'tkt_1');
      expect(values.last.first.ticketId, 'tkt_1');

      await sub.cancel();
      watcher.dispose();
    });

    test('State machine delete event removes row', () async {
      final eventController = StreamController<WatcherEvent<SupportTicketModel>>.broadcast();

      final watcher = SupabaseWatcherStateMachine<SupportTicketModel>(
        fetcher: () async => [
          const SupportTicketModel(ticketId: 'tkt_1', subject: 'A', status: 'open', priority: 'normal'),
          const SupportTicketModel(ticketId: 'tkt_2', subject: 'B', status: 'open', priority: 'normal'),
        ],
        getId: (t) => t.ticketId,
        eventStream: eventController.stream,
      );

      final values = <List<SupportTicketModel>>[];
      final sub = watcher.stream().listen(values.add);
      await pumpEventQueue();

      expect(watcher.cachedList.length, 2);

      // Push delete event for tkt_1
      eventController.add(const WatcherEvent.delete('tkt_1'));
      await pumpEventQueue();

      expect(watcher.cachedList.length, 1);
      expect(watcher.cachedList.first.ticketId, 'tkt_2');
      expect(values.last.length, 1);

      await sub.cancel();
      await eventController.close();
      watcher.dispose();
    });
  });
}
