import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/shared_appointments_store.dart';
import '../mappers/appointment_supabase_mapper.dart';
import '../supabase_bootstrap.dart';

/// Supabase Repository for Appointments.
/// Replaces Firestore `appointments/{appointmentId}` queries and streams.
class SupabaseAppointmentRepository {
  SupabaseAppointmentRepository._();

  static final SupabaseAppointmentRepository instance =
      SupabaseAppointmentRepository._();

  SupabaseClient get _client => SupabaseBootstrap.client;

  Future<void> save(
    DoctorNectAppointmentRecord record, {
    String? patientId,
  }) async {
    if (!SupabaseBootstrap.isReady) return;

    final resolvedPatientId = patientId ?? record.patientId;
    final row = AppointmentSupabaseMapper.toRow(
      record,
      patientId: resolvedPatientId,
    );

    await _client.from('appointments').upsert(row, onConflict: 'appointment_id');
  }

  Future<List<DoctorNectAppointmentRecord>> fetchForDoctor(
    String doctorId, {
    bool preferCache = false,
  }) async {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) return const [];

    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 365));
      final res = await _client
          .from('appointments')
          .select()
          .eq('doctor_id', doctorId)
          .gte('date_time', cutoff.toIso8601String())
          .order('date_time', ascending: false)
          .limit(200);

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map(AppointmentSupabaseMapper.fromRow)
          .whereType<DoctorNectAppointmentRecord>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<DoctorNectAppointmentRecord>> fetchForPatient(
    String patientId, {
    bool preferCache = false,
  }) async {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) return const [];

    try {
      final res = await _client
          .from('appointments')
          .select()
          .eq('patient_id', patientId)
          .order('date_time', ascending: false)
          .limit(100);

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows
          .map(AppointmentSupabaseMapper.fromRow)
          .whereType<DoctorNectAppointmentRecord>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Real-time appointment stream for a Patient's bookings.
  /// CONVERSION RULE: Single .eq filter -> uses Supabase `.stream()`.
  Stream<List<DoctorNectAppointmentRecord>> watchForPatient(String patientId) {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) {
      return const Stream.empty();
    }

    return _client
        .from('appointments')
        .stream(primaryKey: ['appointment_id'])
        .eq('patient_id', patientId)
        .order('date_time', ascending: false)
        .map((rows) => rows
            .map(AppointmentSupabaseMapper.fromRow)
            .whereType<DoctorNectAppointmentRecord>()
            .toList());
  }

  /// Real-time appointment stream for a Doctor's schedule.
  /// CONVERSION RULE:
  /// 1. Subscribes FIRST to PostgreSQL Realtime channel.
  /// 2. Performs initial query upon subscription and on channel reconnects.
  /// 3. Merges and dedupes all incoming mutations by appointment_id.
  /// 4. Handles token refresh via FirebaseAuth.instance.idTokenChanges().
  Stream<List<DoctorNectAppointmentRecord>> watchForDoctor(String doctorId) {
    if (!SupabaseBootstrap.isReady || doctorId.isEmpty) {
      return const Stream.empty();
    }

    late final StreamController<List<DoctorNectAppointmentRecord>> controller;
    RealtimeChannel? channel;
    StreamSubscription<fb.User?>? authSub;
    final recordsMap = <String, DoctorNectAppointmentRecord>{};

    Future<void> syncFromDatabase() async {
      try {
        final records = await fetchForDoctor(doctorId);
        for (final r in records) {
          recordsMap[r.id] = r;
        }
        if (!controller.isClosed) {
          final sorted = recordsMap.values.toList()
            ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
          controller.add(sorted);
        }
      } catch (_) {}
    }

    controller = StreamController<List<DoctorNectAppointmentRecord>>.broadcast(
      onListen: () async {
        // 1. Subscribe FIRST to the channel
        channel = _client.channel('public:appointments:doctor:$doctorId')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'appointments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'doctor_id',
              value: doctorId,
            ),
            callback: (payload) {
              final eventType = payload.eventType;
              if (eventType == PostgresChangeEvent.delete) {
                final oldId = payload.oldRecord['appointment_id'] as String?;
                if (oldId != null) {
                  recordsMap.remove(oldId);
                }
              } else {
                final record =
                    AppointmentSupabaseMapper.fromRow(payload.newRecord);
                if (record != null) {
                  recordsMap[record.id] = record;
                }
              }
              if (!controller.isClosed) {
                final sorted = recordsMap.values.toList()
                  ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
                controller.add(sorted);
              }
            },
          );

        // 2. On subscription established or reconnected, sync from DB
        channel!.subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await syncFromDatabase();
          }
        });

        // 3. Listen to token refresh / re-auth to resync
        if (Firebase.apps.isNotEmpty) {
          authSub = fb.FirebaseAuth.instance.idTokenChanges().listen((user) async {
            if (user != null && !controller.isClosed) {
              await syncFromDatabase();
            }
          });
        }
      },
      onCancel: () async {
        await authSub?.cancel();
        if (channel != null) {
          await _client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }
}
