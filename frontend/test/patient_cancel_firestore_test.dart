import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';

import 'helpers/booking_fixtures.dart';

void main() {
  final store = SharedAppointmentsStore.instance;

  tearDown(() {
    SharedAppointmentsStore.debugPersistOverride = null;
    SharedAppointmentsStore.debugSupabaseCancelOverride = null;
    SupabaseBootstrap.isReady = false;
    store.mergeFromFirestore(const []);
  });

  Future<List<String>> cancelWithMirror(
    Future<void> Function(String appointmentId, String reason) mirror,
  ) async {
    final order = <String>[];
    SharedAppointmentsStore.debugPersistOverride = (record) async {
      order.add('firestore:${record.doctorStatus.name}');
    };
    SharedAppointmentsStore.debugSupabaseCancelOverride = (appointmentId, reason) async {
      order.add('supabase');
      await mirror(appointmentId, reason);
    };
    SupabaseBootstrap.isReady = true;
    store.mergeFromFirestore([
      bookingRecord(id: 'rec-cancel', appointmentId: 'apt-cancel'),
    ]);
    await store.cancelByPatient('rec-cancel', reason: 'plans changed');
    return order;
  }

  test('patient cancel persists Firestore before a successful Supabase mirror', () async {
    final order = await cancelWithMirror((_, __) async {});
    expect(order, ['firestore:${AppointmentStatus.cancelled.name}', 'supabase']);
  });

  test('patient cancel persists Firestore when the Supabase mirror throws', () async {
    final order = await cancelWithMirror((_, __) async {
      throw StateError('supabase down');
    });
    expect(order.first, 'firestore:${AppointmentStatus.cancelled.name}');
    expect(order, contains('supabase'));
  });

  test('patient cancel updates in-memory record cancellation reason and status', () async {
    DoctorNectAppointmentRecord? persistedRecord;
    SharedAppointmentsStore.debugPersistOverride = (record) async {
      persistedRecord = record;
    };
    store.mergeFromFirestore([
      bookingRecord(id: 'rec-1', appointmentId: 'apt-1'),
    ]);

    await store.cancelByPatient('rec-1', reason: 'Emergency personal conflict');

    final updated = store.findRecordById('rec-1');
    expect(updated, isNotNull);
    expect(updated!.doctorStatus, AppointmentStatus.cancelled);
    expect(updated.cancellationReason, 'Emergency personal conflict');
    expect(updated.isCancelled, isTrue);
    expect(persistedRecord, isNotNull);
    expect(persistedRecord!.doctorStatus, AppointmentStatus.cancelled);
    expect(persistedRecord!.cancellationReason, 'Emergency personal conflict');
  });

  test('patient cancel rejects completed or in-progress appointments', () async {
    store.mergeFromFirestore([
      bookingRecord(id: 'rec-completed', appointmentId: 'apt-c').copyWith(
        doctorStatus: AppointmentStatus.completed,
      ),
      bookingRecord(id: 'rec-inprogress', appointmentId: 'apt-ip').copyWith(
        doctorStatus: AppointmentStatus.inProgress,
      ),
      bookingRecord(id: 'rec-noshow', appointmentId: 'apt-ns').copyWith(
        doctorStatus: AppointmentStatus.noShow,
      ),
    ]);

    expect(
      () => store.cancelByPatient('rec-completed', reason: 'Too late'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => store.cancelByPatient('rec-inprogress', reason: 'Ongoing visit'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => store.cancelByPatient('rec-noshow', reason: 'Already marked noShow'),
      throwsA(isA<StateError>()),
    );
  });
}
