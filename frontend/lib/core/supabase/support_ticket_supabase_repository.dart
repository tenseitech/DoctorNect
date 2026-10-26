import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_bootstrap.dart';
import 'supabase_watcher_state_machine.dart';

class SupportTicketModel {
  const SupportTicketModel({
    required this.ticketId,
    String? issueType,
    String? subject,
    String? message,
    required this.status,
    String? priority,
    this.category,
    this.screenshotName,
    this.userId,
    this.patientId,
    this.doctorId,
    this.storeId,
    this.labId,
    this.ambulanceId,
    this.role,
    this.createdAt,
    this.updatedAt,
  })  : issueType = issueType ?? subject ?? category ?? 'Other',
        message = message ?? '',
        priority = priority ?? 'normal';

  factory SupportTicketModel.fromJson(Map<String, dynamic> json) {
    final cat = (json['category'] as String?)?.trim();
    return SupportTicketModel(
      ticketId: (json['ticket_id'] as String?)?.trim() ?? '',
      issueType: (json['issue_type'] as String?)?.trim() ??
          (json['subject'] as String?)?.trim() ??
          cat ??
          'Other',
      message: (json['message'] as String?)?.trim() ?? '',
      status: (json['status'] as String?)?.trim() ?? 'open',
      priority: (json['priority'] as String?)?.trim() ?? 'normal',
      category: cat,
      screenshotName: (json['screenshot_name'] as String?)?.trim(),
      userId: (json['user_id'] as String?)?.trim() ??
          (json['firebase_uid'] as String?)?.trim(),
      patientId: (json['patient_id'] as String?)?.trim(),
      doctorId: (json['doctor_id'] as String?)?.trim(),
      storeId: (json['store_id'] as String?)?.trim(),
      labId: (json['lab_id'] as String?)?.trim(),
      ambulanceId: (json['ambulance_id'] as String?)?.trim(),
      role: (json['role'] as String?)?.trim(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  final String ticketId;
  final String issueType;
  final String message;
  final String status;
  final String priority;
  final String? category;
  final String? screenshotName;
  final String? userId;
  final String? patientId;
  final String? doctorId;
  final String? storeId;
  final String? labId;
  final String? ambulanceId;
  final String? role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Compatibility getters
  String get subject => issueType;

  Map<String, dynamic> toJson() => {
        'ticket_id': ticketId,
        'issue_type': issueType,
        'subject': issueType,
        'priority': priority,
        'message': message,
        'status': status,
        if (screenshotName != null) 'screenshot_name': screenshotName,
        if (userId != null) 'user_id': userId,
        if (patientId != null) 'patient_id': patientId,
        if (doctorId != null) 'doctor_id': doctorId,
        if (storeId != null) 'store_id': storeId,
        if (labId != null) 'lab_id': labId,
        if (ambulanceId != null) 'ambulance_id': ambulanceId,
        if (role != null) 'role': role,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };
}

class TicketMessageModel {
  const TicketMessageModel({
    required this.messageId,
    required this.ticketId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.text,
    this.createdAt,
  });

  factory TicketMessageModel.fromJson(Map<String, dynamic> json) {
    return TicketMessageModel(
      messageId: (json['message_id'] as String?)?.trim() ?? '',
      ticketId: (json['ticket_id'] as String?)?.trim() ?? '',
      senderId: (json['sender_id'] as String?)?.trim() ?? '',
      senderName: (json['sender_name'] as String?)?.trim() ?? 'User',
      senderRole: (json['sender_role'] as String?)?.trim() ?? 'patient',
      text: (json['text'] as String?)?.trim() ??
          (json['message_text'] as String?)?.trim() ??
          '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  final String messageId;
  final String ticketId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String text;
  final DateTime? createdAt;

  // Compatibility getter
  String get messageText => text;

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'ticket_id': ticketId,
        'sender_id': senderId,
        'sender_name': senderName,
        'sender_role': senderRole,
        'text': text,
        'message_text': text,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}

class SupportTicketSupabaseRepository {
  SupportTicketSupabaseRepository._();
  static final SupportTicketSupabaseRepository instance =
      SupportTicketSupabaseRepository._();

  SupabaseClient? _mockClient;

  @visibleForTesting
  void setClientForTesting(SupabaseClient client) {
    _mockClient = client;
  }

  SupabaseClient get _client => _mockClient ?? SupabaseBootstrap.client;

  Future<String> createTicket({
    required String message,
    String? issueType,
    String? subject,
    String? category,
    String? screenshotName,
    String? patientId,
    String? doctorId,
    String? storeId,
    String? labId,
    String? ambulanceId,
    String? role,
    String? userId,
  }) async {
    final ticketId = 'tkt_${DateTime.now().millisecondsSinceEpoch}';
    final resolvedIssueType = (issueType ?? subject ?? category ?? 'Other').trim();
    // Validate constraint: 'Appointment', 'Records', 'Technical', 'Other'
    final validTypes = const ['Appointment', 'Records', 'Technical', 'Other'];
    final normalizedIssueType =
        validTypes.contains(resolvedIssueType) ? resolvedIssueType : 'Other';

    final payload = <String, dynamic>{
      'ticket_id': ticketId,
      'issue_type': normalizedIssueType,
      'message': message,
      'status': 'open',
      if (screenshotName != null && screenshotName.isNotEmpty)
        'screenshot_name': screenshotName,
      if (patientId != null && patientId.isNotEmpty) 'patient_id': patientId,
      if (doctorId != null && doctorId.isNotEmpty) 'doctor_id': doctorId,
      if (storeId != null && storeId.isNotEmpty) 'store_id': storeId,
      if (labId != null && labId.isNotEmpty) 'lab_id': labId,
      if (ambulanceId != null && ambulanceId.isNotEmpty)
        'ambulance_id': ambulanceId,
      if (role != null && role.isNotEmpty) 'role': role,
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
    };

    await _client.from('support_tickets').insert(payload);

    return ticketId;
  }

  Future<void> sendMessage({
    required String ticketId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String text,
  }) async {
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
    await _client.from('support_ticket_messages').insert({
      'message_id': messageId,
      'ticket_id': ticketId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_role': senderRole,
      'text': text,
    });
  }

  Future<List<SupportTicketModel>> fetchMyTickets({
    String? patientId,
    String? doctorId,
    String? storeId,
    String? labId,
    String? ambulanceId,
  }) async {
    var query = _client.from('support_tickets').select();
    if (patientId != null && patientId.isNotEmpty) {
      query = query.eq('patient_id', patientId);
    } else if (doctorId != null && doctorId.isNotEmpty) {
      query = query.eq('doctor_id', doctorId);
    } else if (storeId != null && storeId.isNotEmpty) {
      query = query.eq('store_id', storeId);
    } else if (labId != null && labId.isNotEmpty) {
      query = query.eq('lab_id', labId);
    } else if (ambulanceId != null && ambulanceId.isNotEmpty) {
      query = query.eq('ambulance_id', ambulanceId);
    }

    final res = await query.order('created_at', ascending: false);
    return (res as List)
        .map((r) => SupportTicketModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<TicketMessageModel>> fetchTicketMessages(String ticketId) async {
    final res = await _client
        .from('support_ticket_messages')
        .select()
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true);
    return (res as List)
        .map((r) => TicketMessageModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  SupabaseWatcherStateMachine<SupportTicketModel> createTicketWatcher({
    String? patientId,
    String? doctorId,
    String? storeId,
    String? labId,
    String? ambulanceId,
    Stream<WatcherEvent<SupportTicketModel>>? eventStream,
  }) {
    return SupabaseWatcherStateMachine<SupportTicketModel>(
      fetcher: () => fetchMyTickets(
        patientId: patientId,
        doctorId: doctorId,
        storeId: storeId,
        labId: labId,
        ambulanceId: ambulanceId,
      ),
      getId: (t) => t.ticketId,
      sort: (list) => list.sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0))),
      eventStream: eventStream,
    );
  }

  SupabaseWatcherStateMachine<TicketMessageModel> createMessageWatcher({
    required String ticketId,
    Stream<WatcherEvent<TicketMessageModel>>? eventStream,
  }) {
    return SupabaseWatcherStateMachine<TicketMessageModel>(
      fetcher: () => fetchTicketMessages(ticketId),
      getId: (m) => m.messageId,
      sort: (list) => list.sort((a, b) =>
          (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0))),
      eventStream: eventStream,
    );
  }

  Stream<List<SupportTicketModel>> watchMyTickets({
    String? patientId,
    String? doctorId,
    String? storeId,
    String? labId,
    String? ambulanceId,
  }) {
    late final StreamController<List<SupportTicketModel>> controller;
    RealtimeChannel? channel;

    Timer? pollTimer;
    controller = StreamController<List<SupportTicketModel>>.broadcast(
      onListen: () async {
        Future<void> syncTickets() async {
          try {
            final updated = await fetchMyTickets(
              patientId: patientId,
              doctorId: doctorId,
              storeId: storeId,
              labId: labId,
              ambulanceId: ambulanceId,
            );
            if (!controller.isClosed) {
              controller.add(updated);
            }
          } catch (e, st) {
            if (!controller.isClosed) {
              controller.addError(e, st);
            }
          }
        }

        await syncTickets();

        if (SupabaseBootstrap.isProduction) {
          // In production: do not open Realtime channel; use periodic polling
          pollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
            if (!controller.isClosed) {
              await syncTickets();
            }
          });
        } else {
          try {
            final filterCol = patientId != null
                ? 'patient_id'
                : (doctorId != null
                    ? 'doctor_id'
                    : (storeId != null
                        ? 'store_id'
                        : (labId != null ? 'lab_id' : 'ambulance_id')));
            final filterVal = patientId ??
                doctorId ??
                storeId ??
                labId ??
                ambulanceId ??
                '';

            channel = _client.channel('public:support_tickets:$filterCol:$filterVal')
              ..onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'support_tickets',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: filterCol,
                  value: filterVal,
                ),
                callback: (payload) async {
                  await syncTickets();
                },
              )
              ..subscribe();
          } catch (e) {
            debugPrint(
                '[SupportTicketSupabaseRepository] Realtime subscription warning: $e');
          }
        }
      },
      onCancel: () async {
        pollTimer?.cancel();
        if (channel != null) {
          try {
            await _client.removeChannel(channel!);
          } catch (_) {}
        }
      },
    );

    return controller.stream;
  }

  Stream<List<TicketMessageModel>> watchTicketMessages(String ticketId) {
    late final StreamController<List<TicketMessageModel>> controller;
    RealtimeChannel? channel;
    Timer? pollTimer;

    controller = StreamController<List<TicketMessageModel>>.broadcast(
      onListen: () async {
        Future<void> syncMessages() async {
          try {
            final updated = await fetchTicketMessages(ticketId);
            if (!controller.isClosed) {
              controller.add(updated);
            }
          } catch (e, st) {
            if (!controller.isClosed) {
              controller.addError(e, st);
            }
          }
        }

        await syncMessages();

        if (SupabaseBootstrap.isProduction) {
          // In production: do not open Realtime channel; use periodic polling
          pollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
            if (!controller.isClosed) {
              await syncMessages();
            }
          });
        } else {
          try {
            channel = _client.channel('public:support_ticket_messages:$ticketId')
              ..onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'support_ticket_messages',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'ticket_id',
                  value: ticketId,
                ),
                callback: (payload) async {
                  await syncMessages();
                },
              )
              ..subscribe();
          } catch (e) {
            debugPrint(
                '[SupportTicketSupabaseRepository] Realtime subscription warning: $e');
          }
        }
      },
      onCancel: () async {
        pollTimer?.cancel();
        if (channel != null) {
          try {
            await _client.removeChannel(channel!);
          } catch (_) {}
        }
      },
    );

    return controller.stream;
  }
}
