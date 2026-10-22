import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_bootstrap.dart';
import 'supabase_watcher_state_machine.dart';

class SupportTicketModel {
  const SupportTicketModel({
    required this.ticketId,
    required this.subject,
    required this.status,
    required this.priority,
    this.userId,
    this.patientId,
    this.doctorId,
    this.storeId,
    this.labId,
    this.ambulanceId,
    this.category,
    this.createdAt,
    this.updatedAt,
  });

  factory SupportTicketModel.fromJson(Map<String, dynamic> json) {
    return SupportTicketModel(
      ticketId: (json['ticket_id'] as String?)?.trim() ?? '',
      subject: (json['subject'] as String?)?.trim() ?? '',
      status: (json['status'] as String?)?.trim() ?? 'open',
      priority: (json['priority'] as String?)?.trim() ?? 'normal',
      userId: (json['user_id'] as String?)?.trim(),
      patientId: (json['patient_id'] as String?)?.trim(),
      doctorId: (json['doctor_id'] as String?)?.trim(),
      storeId: (json['store_id'] as String?)?.trim(),
      labId: (json['lab_id'] as String?)?.trim(),
      ambulanceId: (json['ambulance_id'] as String?)?.trim(),
      category: (json['category'] as String?)?.trim(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  final String ticketId;
  final String subject;
  final String status;
  final String priority;
  final String? userId;
  final String? patientId;
  final String? doctorId;
  final String? storeId;
  final String? labId;
  final String? ambulanceId;
  final String? category;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'ticket_id': ticketId,
        'subject': subject,
        'status': status,
        'priority': priority,
        if (userId != null) 'user_id': userId,
        if (patientId != null) 'patient_id': patientId,
        if (doctorId != null) 'doctor_id': doctorId,
        if (storeId != null) 'store_id': storeId,
        if (labId != null) 'lab_id': labId,
        if (ambulanceId != null) 'ambulance_id': ambulanceId,
        if (category != null) 'category': category,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };
}

class TicketMessageModel {
  const TicketMessageModel({
    required this.messageId,
    required this.ticketId,
    required this.senderId,
    required this.senderRole,
    required this.messageText,
    this.createdAt,
  });

  factory TicketMessageModel.fromJson(Map<String, dynamic> json) {
    return TicketMessageModel(
      messageId: (json['message_id'] as String?)?.trim() ?? '',
      ticketId: (json['ticket_id'] as String?)?.trim() ?? '',
      senderId: (json['sender_id'] as String?)?.trim() ?? '',
      senderRole: (json['sender_role'] as String?)?.trim() ?? 'patient',
      messageText: (json['message_text'] as String?)?.trim() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  final String messageId;
  final String ticketId;
  final String senderId;
  final String senderRole;
  final String messageText;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'ticket_id': ticketId,
        'sender_id': senderId,
        'sender_role': senderRole,
        'message_text': messageText,
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

  SupabaseClient get _client =>
      _mockClient ?? SupabaseBootstrap.client;

  Future<String> createTicket({
    required String subject,
    required String message,
    String? category,
    String? patientId,
    String? doctorId,
    String? storeId,
    String? labId,
    String? ambulanceId,
    String? role,
  }) async {
    final ticketId = 'tkt_${DateTime.now().millisecondsSinceEpoch}';
    final payload = <String, dynamic>{
      'ticket_id': ticketId,
      'subject': subject,
      'status': 'open',
      'priority': 'normal',
      if (category != null) 'category': category,
      if (patientId != null) 'patient_id': patientId,
      if (doctorId != null) 'doctor_id': doctorId,
      if (storeId != null) 'store_id': storeId,
      if (labId != null) 'lab_id': labId,
      if (ambulanceId != null) 'ambulance_id': ambulanceId,
      if (role != null) 'role': role,
    };

    await _client.from('support_tickets').insert(payload);

    if (message.trim().isNotEmpty) {
      await sendMessage(
        ticketId: ticketId,
        senderId: patientId ?? doctorId ?? storeId ?? labId ?? ambulanceId ?? 'user',
        senderRole: role ?? 'patient',
        messageText: message,
      );
    }

    return ticketId;
  }

  Future<void> sendMessage({
    required String ticketId,
    required String senderId,
    required String senderRole,
    required String messageText,
  }) async {
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
    await _client.from('support_ticket_messages').insert({
      'message_id': messageId,
      'ticket_id': ticketId,
      'sender_id': senderId,
      'sender_role': senderRole,
      'message_text': messageText,
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
}
