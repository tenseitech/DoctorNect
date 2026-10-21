import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/supabase/repositories/supabase_ambulance_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_lab_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_pharmacy_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

void main() {
  setUp(() {
    SupabaseBootstrap.resetForTesting();
  });

  group('SupabasePharmacyRepository (Phase D)', () {
    test('fetchMedicalStore returns null when Supabase is not ready or id empty', () async {
      final res1 = await SupabasePharmacyRepository.instance.fetchMedicalStore('');
      final res2 = await SupabasePharmacyRepository.instance.fetchMedicalStore('store_123');
      expect(res1, isNull);
      expect(res2, isNull);
    });

    test('fetchVerifiedStores returns empty list when Supabase is not ready', () async {
      final res = await SupabasePharmacyRepository.instance.fetchVerifiedStores();
      expect(res, isEmpty);
    });

    test('fetchDeliveriesForStore returns empty list when Supabase is not ready', () async {
      final res = await SupabasePharmacyRepository.instance.fetchDeliveriesForStore('store_123');
      expect(res, isEmpty);
    });

    test('updateDeliveryStatus returns false when Supabase is not ready or id empty', () async {
      final res1 = await SupabasePharmacyRepository.instance.updateDeliveryStatus(
        deliveryId: '',
        newStatus: 'viewed',
      );
      final res2 = await SupabasePharmacyRepository.instance.updateDeliveryStatus(
        deliveryId: 'del_123',
        newStatus: 'viewed',
      );
      expect(res1, isFalse);
      expect(res2, isFalse);
    });

    test('watchDeliveriesForStore returns empty stream when not ready', () {
      final stream = SupabasePharmacyRepository.instance.watchDeliveriesForStore('store_123');
      expect(stream, emitsDone);
    });
  });

  group('SupabaseLabRepository (Phase D)', () {
    test('fetchLabProfile returns null when Supabase is not ready or id empty', () async {
      final res1 = await SupabaseLabRepository.instance.fetchLabProfile('');
      final res2 = await SupabaseLabRepository.instance.fetchLabProfile('lab_123');
      expect(res1, isNull);
      expect(res2, isNull);
    });

    test('fetchVerifiedLabs returns empty list when Supabase is not ready', () async {
      final res = await SupabaseLabRepository.instance.fetchVerifiedLabs();
      expect(res, isEmpty);
    });

    test('fetchCatalogTests returns empty list when Supabase is not ready', () async {
      final res = await SupabaseLabRepository.instance.fetchCatalogTests('lab_123');
      expect(res, isEmpty);
    });

    test('fetchBookingsForLab returns empty list when Supabase is not ready', () async {
      final res = await SupabaseLabRepository.instance.fetchBookingsForLab('lab_123');
      expect(res, isEmpty);
    });

    test('updateLabBookingStatus returns false when Supabase is not ready or id empty', () async {
      final res = await SupabaseLabRepository.instance.updateLabBookingStatus(
        bookingId: 'bkg_123',
        newStatus: 'sampleCollected',
      );
      expect(res, isFalse);
    });

    test('watchBookingsForLab returns empty stream when not ready', () {
      final stream = SupabaseLabRepository.instance.watchBookingsForLab('lab_123');
      expect(stream, emitsDone);
    });
  });

  group('SupabaseAmbulanceRepository (Phase D)', () {
    test('fetchProfile returns null when Supabase is not ready or id empty', () async {
      final res1 = await SupabaseAmbulanceRepository.instance.fetchProfile('');
      final res2 = await SupabaseAmbulanceRepository.instance.fetchProfile('amb_123');
      expect(res1, isNull);
      expect(res2, isNull);
    });

    test('fetchAvailableAmbulances returns empty list when Supabase is not ready', () async {
      final res = await SupabaseAmbulanceRepository.instance.fetchAvailableAmbulances();
      expect(res, isEmpty);
    });

    test('fetchPendingBroadcasts returns empty list when Supabase is not ready', () async {
      final res = await SupabaseAmbulanceRepository.instance.fetchPendingBroadcasts();
      expect(res, isEmpty);
    });

    test('acceptAmbulanceRequest returns false when Supabase is not ready or id empty', () async {
      final res1 = await SupabaseAmbulanceRepository.instance.acceptAmbulanceRequest(broadcastId: '');
      final res2 = await SupabaseAmbulanceRepository.instance.acceptAmbulanceRequest(broadcastId: 'bc_123');
      expect(res1, isFalse);
      expect(res2, isFalse);
    });

    test('updateDriverLocation returns false when Supabase is not ready or id empty', () async {
      final res = await SupabaseAmbulanceRepository.instance.updateDriverLocation(
        broadcastId: 'bc_123',
        driverId: 'drv_123',
        latitude: 18.5204,
        longitude: 73.8567,
      );
      expect(res, isFalse);
    });

    test('getTripLocation returns null when Supabase is not ready or id empty', () async {
      final res = await SupabaseAmbulanceRepository.instance.getTripLocation('bc_123');
      expect(res, isNull);
    });

    test('completeTrip returns false when Supabase is not ready or id empty', () async {
      final res = await SupabaseAmbulanceRepository.instance.completeTrip('bc_123');
      expect(res, isFalse);
    });

    test('cancelTrip returns false when Supabase is not ready or id empty', () async {
      final res = await SupabaseAmbulanceRepository.instance.cancelTrip(broadcastId: 'bc_123');
      expect(res, isFalse);
    });

    test('watchIncomingRequests returns empty stream when not ready', () {
      final stream = SupabaseAmbulanceRepository.instance.watchIncomingRequests('drv_123');
      expect(stream, emitsDone);
    });

    test('watchLocationSignals returns empty stream when not ready', () {
      final stream = SupabaseAmbulanceRepository.instance.watchLocationSignals('bc_123');
      expect(stream, emitsDone);
    });
  });
}
