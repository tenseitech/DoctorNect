import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/shared_appointments_store.dart';
import '../mappers/appointment_supabase_mapper.dart';
import '../supabase_bootstrap.dart';
import '../supabase_stream_table.dart';

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
      if (!kReleaseMode && debugTableFetcher != null) {
        final rows = await debugTableFetcher!('appointments');
        return rows
            .map(AppointmentSupabaseMapper.fromRow)
            .whereType<DoctorNectAppointmentRecord>()
            .toList();
      }

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
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SupabaseAppointmentRepository] fetchForDoctor error: $e\n$st');
      }
      rethrow;
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
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SupabaseAppointmentRepository] fetchForPatient error: $e\n$st');
      }
      rethrow;
    }
  }

  /// Real-time appointment stream for a Patient's bookings.
  /// CONVERSION RULE: Single .eq filter -> uses Supabase `.stream()`.
  Stream<List<DoctorNectAppointmentRecord>> watchForPatient(String patientId) {
    if (!SupabaseBootstrap.isReady || patientId.isEmpty) {
      return const Stream.empty();
    }

    if (SupabaseBootstrap.isProduction) {
      return streamTable(
        table: 'appointments',
        primaryKey: ['appointment_id'],
        filterColumn: 'patient_id',
        filterValue: patientId,
      ).map((rows) {
        final records = rows
            .map(AppointmentSupabaseMapper.fromRow)
            .whereType<DoctorNectAppointmentRecord>()
            .toList();
        records.sort((a, b) => b.dateTime.compareTo(a.dateTime));
        return records;
      });
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
        recordsMap.clear();
        for (final r in records) {
          recordsMap[r.id] = r;
        }
        if (!controller.isClosed) {
          final sorted = recordsMap.values.toList()
            ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
          controller.add(sorted);
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[SupabaseAppointmentRepository] sync error: $e\n$st');
        }
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    }

    Timer? pollTimer;
    controller = StreamController<List<DoctorNectAppointmentRecord>>.broadcast(
      onListen: () async {
        // 0. Emit latest cached appointments immediately to new listeners
        if (recordsMap.isNotEmpty && !controller.isClosed) {
          final cached = recordsMap.values.toList()
            ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
          controller.add(cached);
        }

        if (SupabaseBootstrap.isProduction) {
          // In production: do NOT open a Realtime WebSocket channel. Use adaptive polling.
          pollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
            if (!controller.isClosed) {
              await syncFromDatabase();
            }
          });
          await syncFromDatabase();
        } else {
          // 1. Subscribe FIRST to the channel in staging
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
        }

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
        pollTimer?.cancel();
        await authSub?.cancel();
        if (channel != null) {
          await _client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }
}
