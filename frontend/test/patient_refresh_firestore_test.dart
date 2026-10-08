import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

import 'helpers/booking_fixtures.dart';

void main() {
  final store = SharedAppointmentsStore.instance;

  tearDown(() {
    SharedAppointmentsStore.debugPatientSupabaseRefresh = null;
    SharedAppointmentsStore.debugPatientFirestoreRefresh = null;
    SupabaseBootstrap.isReady = false;
    store.mergeFromFirestore(const []);
  });

  test('Firestore booking remains when Supabase is empty or throws', () async {
    SupabaseBootstrap.isReady = true;
    SharedAppointmentsStore.debugPatientFirestoreRefresh = (_) async {
      return [bookingRecord(id: 'fs-1', doctorName: 'From Firestore')];
    };

    SharedAppointmentsStore.debugPatientSupabaseRefresh = (_) async => const [];
    await store.refreshForPatient('pat-1');
    expect(store.records.map((r) => r.id), ['fs-1']);

    SharedAppointmentsStore.debugPatientSupabaseRefresh = (_) async {
      throw StateError('supabase down');
    };
    await store.refreshForPatient('pat-1');
    expect(store.records.single.id, 'fs-1');
    expect(store.records.single.doctorName, 'From Firestore');
  });

  test('the same appointment id keeps the Firestore row', () async {
    SupabaseBootstrap.isReady = true;
    SharedAppointmentsStore.debugPatientSupabaseRefresh = (_) async {
      return [bookingRecord(id: 'same', doctorName: 'From Supabase')];
    };
    SharedAppointmentsStore.debugPatientFirestoreRefresh = (_) async {
      return [bookingRecord(id: 'same', doctorName: 'From Firestore')];
    };

    await store.refreshForPatient('pat-1');

    expect(store.records.single.doctorName, 'From Firestore');
  });
}
