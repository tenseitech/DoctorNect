import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/config/doctor_patient_cutover_flag.dart';
import 'package:medibond/core/supabase/support_ticket_supabase_repository.dart';
import 'package:medibond/core/supabase/supabase_watcher_state_machine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupportTicketModel Mapping Tests', () {
    test('parses from complete JSON correctly', () {
      final json = {
        'ticket_id': 'tkt_123',
        'issue_type': 'Technical',
        'message': 'Cannot upload prescription',
        'status': 'open',
        'screenshot_name': 'error.png',
        'user_id': 'user_456',
        'patient_id': 'patient_789',
        'doctor_id': 'doc_001',
        'created_at': '2026-10-21T10:00:00.000Z',
        'updated_at': '2026-10-21T10:05:00.000Z',
      };

      final model = SupportTicketModel.fromJson(json);

      expect(model.ticketId, 'tkt_123');
      expect(model.issueType, 'Technical');
      expect(model.subject, 'Technical');
      expect(model.message, 'Cannot upload prescription');
      expect(model.status, 'open');
      expect(model.screenshotName, 'error.png');
      expect(model.userId, 'user_456');
      expect(model.patientId, 'patient_789');
      expect(model.doctorId, 'doc_001');
      expect(model.createdAt, DateTime.parse('2026-10-21T10:00:00.000Z'));
      expect(model.updatedAt, DateTime.parse('2026-10-21T10:05:00.000Z'));

      final out = model.toJson();
      expect(out['ticket_id'], 'tkt_123');
      expect(out['issue_type'], 'Technical');
      expect(out['message'], 'Cannot upload prescription');
      expect(out['status'], 'open');
      expect(out['screenshot_name'], 'error.png');
      expect(out['user_id'], 'user_456');
      expect(out['patient_id'], 'patient_789');
    });

    test('handles fallback fields for legacy JSON gracefully', () {
      final json = {
        'ticket_id': 'tkt_legacy',
        'subject': 'Appointment',
        'message': 'Reschedule requested',
        'firebase_uid': 'fb_uid_123',
      };

      final model = SupportTicketModel.fromJson(json);

      expect(model.ticketId, 'tkt_legacy');
      expect(model.issueType, 'Appointment');
      expect(model.userId, 'fb_uid_123');
      expect(model.status, 'open');
      expect(model.priority, 'normal');
      expect(model.createdAt, isNull);
    });
  });

  group('TicketMessageModel Mapping Tests', () {
    test('parses from complete JSON correctly', () {
      final json = {
        'message_id': 'msg_001',
        'ticket_id': 'tkt_123',
        'sender_id': 'user_456',
        'sender_name': 'Dr. Sharma',
        'sender_role': 'doctor',
        'text': 'We are looking into this.',
        'created_at': '2026-10-21T10:01:00.000Z',
      };

      final model = TicketMessageModel.fromJson(json);

      expect(model.messageId, 'msg_001');
      expect(model.ticketId, 'tkt_123');
      expect(model.senderId, 'user_456');
      expect(model.senderName, 'Dr. Sharma');
      expect(model.senderRole, 'doctor');
      expect(model.text, 'We are looking into this.');
      expect(model.messageText, 'We are looking into this.');
      expect(model.createdAt, DateTime.parse('2026-10-21T10:01:00.000Z'));

      final out = model.toJson();
      expect(out['message_id'], 'msg_001');
      expect(out['ticket_id'], 'tkt_123');
      expect(out['sender_id'], 'user_456');
      expect(out['sender_name'], 'Dr. Sharma');
      expect(out['sender_role'], 'doctor');
      expect(out['text'], 'We are looking into this.');
    });

    test('handles legacy message_text field gracefully', () {
      final json = {
        'message_id': 'msg_leg',
        'ticket_id': 'tkt_123',
        'sender_id': 'user_456',
        'message_text': 'Legacy message format',
      };

      final model = TicketMessageModel.fromJson(json);
      expect(model.text, 'Legacy message format');
      expect(model.senderName, 'User');
      expect(model.senderRole, 'patient');
    });
  });

  group('SupportTicket Watcher State Machine Tests', () {
    test('watcher fetches initial tickets, receives upsert and delete', () async {
      final initialTicket = SupportTicketModel(
        ticketId: 'tkt_init',
        issueType: 'Appointment',
        message: 'Initial ticket',
        status: 'open',
        createdAt: DateTime(2026, 10, 21, 9, 0),
      );

      final eventController =
          StreamController<WatcherEvent<SupportTicketModel>>.broadcast();

      final watcher = SupportTicketSupabaseRepository.instance.createTicketWatcher(
        patientId: 'patient_test',
        eventStream: eventController.stream,
      );

      // Create a test-isolated watcher using injected fetcher
      final isolatedWatcher = SupabaseWatcherStateMachine<SupportTicketModel>(
        fetcher: () async => [initialTicket],
        getId: (t) => t.ticketId,
        sort: (list) => list.sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0))),
        eventStream: eventController.stream,
      );

      final emitted = <List<SupportTicketModel>>[];
      final sub = isolatedWatcher.stream().listen(emitted.add);

      // Wait for initial fetch
      await pumpEventQueue();

      expect(emitted.isNotEmpty, isTrue);
      expect(emitted.last.length, 1);
      expect(emitted.last.first.ticketId, 'tkt_init');

      // Incremental upsert
      final newTicket = SupportTicketModel(
        ticketId: 'tkt_new',
        issueType: 'Technical',
        message: 'App crash',
        status: 'in_progress',
        createdAt: DateTime(2026, 10, 21, 10, 0),
      );
      eventController.add(WatcherEvent.upsert(newTicket));
      await pumpEventQueue();

      expect(emitted.last.length, 2);
      expect(emitted.last.first.ticketId, 'tkt_new'); // newer item sorted first

      // Incremental delete
      eventController.add(const WatcherEvent.delete('tkt_init'));
      await pumpEventQueue();

      expect(emitted.last.length, 1);
      expect(emitted.last.first.ticketId, 'tkt_new');

      await sub.cancel();
      isolatedWatcher.dispose();
      await eventController.close();
      watcher.dispose();
    });

    test('message watcher receives incremental message updates', () async {
      final initialMsg = TicketMessageModel(
        messageId: 'msg_1',
        ticketId: 'tkt_100',
        senderId: 'pat_1',
        senderName: 'Patient',
        senderRole: 'patient',
        text: 'Hello',
        createdAt: DateTime(2026, 10, 21, 11, 0),
      );

      final eventController =
          StreamController<WatcherEvent<TicketMessageModel>>.broadcast();

      final isolatedWatcher = SupabaseWatcherStateMachine<TicketMessageModel>(
        fetcher: () async => [initialMsg],
        getId: (m) => m.messageId,
        sort: (list) => list.sort((a, b) => (a.createdAt ?? DateTime(0))
            .compareTo(b.createdAt ?? DateTime(0))),
        eventStream: eventController.stream,
      );

      final emitted = <List<TicketMessageModel>>[];
      final sub = isolatedWatcher.stream().listen(emitted.add);

      await pumpEventQueue();
      expect(emitted.last.length, 1);

      final replyMsg = TicketMessageModel(
        messageId: 'msg_2',
        ticketId: 'tkt_100',
        senderId: 'support_1',
        senderName: 'Support Agent',
        senderRole: 'support',
        text: 'How can I assist you?',
        createdAt: DateTime(2026, 10, 21, 11, 2),
      );
      eventController.add(WatcherEvent.upsert(replyMsg));
      await pumpEventQueue();

      expect(emitted.last.length, 2);
      expect(emitted.last.last.text, 'How can I assist you?');

      await sub.cancel();
      isolatedWatcher.dispose();
      await eventController.close();
    });
  });

  group('Cutover flag toggles', () {
    test('DoctorPatientCutoverFlag can be enabled and disabled', () {
      DoctorPatientCutoverFlag.debugOverride = true;
      expect(DoctorPatientCutoverFlag.isEnabled, isTrue);

      DoctorPatientCutoverFlag.debugOverride = false;
      expect(DoctorPatientCutoverFlag.isEnabled, isFalse);

      DoctorPatientCutoverFlag.debugOverride = null;
    });
  });
}
