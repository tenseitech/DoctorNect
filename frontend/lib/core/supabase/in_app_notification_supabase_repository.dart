import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/app_notification.dart';
import '../notifications/doctor_notification_trigger.dart';
import '../notifications/patient_notification_trigger.dart';
import 'supabase_bootstrap.dart';
import 'supabase_stream_table.dart';
import 'supabase_watcher_state_machine.dart';

class InAppNotificationSupabaseRepository {
  InAppNotificationSupabaseRepository._();
  static final InAppNotificationSupabaseRepository instance =
      InAppNotificationSupabaseRepository._();

  SupabaseClient? _mockClient;

  @visibleForTesting
  void setClientForTesting(SupabaseClient client) {
    _mockClient = client;
  }

  static Future<void> Function(String notificationId)? _debugMarkReadOverride;

  @visibleForTesting
  static Future<void> Function(String notificationId)? get debugMarkReadOverride =>
      _debugMarkReadOverride;

  @visibleForTesting
  static set debugMarkReadOverride(
    Future<void> Function(String notificationId)? value,
  ) {
    assert(() {
      if (value != null && (kReleaseMode || debugForceReleaseMode)) {
        throw AssertionError(
          'debugMarkReadOverride must not be set in release mode',
        );
      }
      return true;
    }());
    _debugMarkReadOverride = value;
  }

  /// Test-only: treat runtime as release (ignores [debugMarkReadOverride] in [markRead]).
  @visibleForTesting
  static bool debugForceReleaseMode = false;

  @visibleForTesting
  void clearClientForTesting() => _mockClient = null;

  @visibleForTesting
  static void resetMarkReadOverrideForTesting() {
    _debugMarkReadOverride = null;
    debugForceReleaseMode = false;
  }

  SupabaseClient get _client => _mockClient ?? SupabaseBootstrap.client;

  static AppNotification? notificationFromRow(Map<String, dynamic> row) {
    try {
      final id = (row['notification_id'] as String?)?.trim() ??
          (row['id'] as String?)?.trim() ??
          '';
      final title = (row['title'] as String?)?.trim() ?? '';
      final body = (row['body'] as String?)?.trim() ?? '';
      if (title.isEmpty || body.isEmpty) return null;

      final doctorTriggerStr = (row['doctor_trigger'] as String?)?.trim();
      final patientTriggerStr = (row['patient_trigger'] as String?)?.trim();

      DoctorNotificationTrigger? doctorTrigger;
      PatientNotificationTrigger? patientTrigger;

      if (doctorTriggerStr != null && doctorTriggerStr.isNotEmpty) {
        for (final t in DoctorNotificationTrigger.values) {
          if (t.name == doctorTriggerStr) {
            doctorTrigger = t;
            break;
          }
        }
      }

      if (patientTriggerStr != null && patientTriggerStr.isNotEmpty) {
        for (final t in PatientNotificationTrigger.values) {
          if (t.name == patientTriggerStr) {
            patientTrigger = t;
            break;
          }
        }
      }

      final NotificationPriority priority;
      final List<NotificationChannelTag> channelTags;
      if (patientTrigger != null) {
        final spec = PatientTriggerCatalog.specFor(patientTrigger);
        priority = spec.priority;
        channelTags = [NotificationChannelTag.app, ...spec.channels];
      } else if (doctorTrigger != null) {
        final spec = DoctorTriggerCatalog.specFor(doctorTrigger);
        priority = spec.priority;
        channelTags = [NotificationChannelTag.app, ...spec.channels];
      } else {
        priority = NotificationPriority.medium;
        channelTags = [NotificationChannelTag.app];
      }

      AppNotificationType type = AppNotificationType.system;
      final typeStr = (row['type'] as String?)?.trim();
      if (typeStr != null && typeStr.isNotEmpty) {
        for (final t in AppNotificationType.values) {
          if (t.name.toLowerCase() == typeStr.toLowerCase()) {
            type = t;
            break;
          }
        }
      }

      final createdAtRaw = row['created_at'];
      final createdAt = createdAtRaw != null
          ? (DateTime.tryParse(createdAtRaw.toString()) ?? DateTime.now())
          : DateTime.now();

      return AppNotification(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        type: type,
        isRead: row['is_read'] == true,
        targetId: (row['target_id'] as String?)?.trim(),
        doctorTrigger: doctorTrigger,
        patientTrigger: patientTrigger,
        priority: priority,
        channelTags: channelTags,
        dedupeKey: (row['dedupe_key'] as String?)?.trim(),
      );
    } catch (e) {
      debugPrint('[InAppNotificationSupabaseRepository] Mapping error: $e');
      return null;
    }
  }

  Future<List<AppNotification>> fetchForRecipient(String recipientUid) async {
    if (!kReleaseMode && debugTableFetcher != null) {
      final rows = await debugTableFetcher!('in_app_notifications');
      final list = <AppNotification>[];
      for (final row in rows) {
        final notif = notificationFromRow(row);
        if (notif != null) list.add(notif);
      }
      return list;
    }

    final res = await _client
        .from('in_app_notifications')
        .select()
        .eq('recipient_uid', recipientUid)
        .order('created_at', ascending: false)
        .limit(50);

    final list = <AppNotification>[];
    for (final row in res as List) {
      final notif = notificationFromRow(row as Map<String, dynamic>);
      if (notif != null) list.add(notif);
    }
    return list;
  }

  Future<void> markRead(String notificationId) async {
    if (notificationId.isEmpty) return;
    final o = _debugMarkReadOverride;
    final releaseLike = kReleaseMode || debugForceReleaseMode;
    if (!releaseLike && o != null) {
      await o(notificationId);
      return;
    }
    await _client.from('in_app_notifications').update({
      'is_read': true,
      'read_at': DateTime.now().toIso8601String(),
    }).eq('notification_id', notificationId);
  }

  Future<void> markAllRead(Iterable<String> notificationIds) async {
    final ids = notificationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;

    for (final id in ids) {
      await markRead(id);
    }
  }

  SupabaseWatcherStateMachine<AppNotification> createWatcher({
    required String recipientUid,
    Stream<WatcherEvent<AppNotification>>? eventStream,
  }) {
    return SupabaseWatcherStateMachine<AppNotification>(
      fetcher: () => fetchForRecipient(recipientUid),
      getId: (n) => n.id,
      sort: (list) => list.sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      eventStream: eventStream,
    );
  }

  Stream<List<AppNotification>> watchForRecipient(String recipientUid) {
    final watcher = createWatcher(recipientUid: recipientUid);
    return watcher.stream();
  }
}
