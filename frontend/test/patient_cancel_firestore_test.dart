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
}
