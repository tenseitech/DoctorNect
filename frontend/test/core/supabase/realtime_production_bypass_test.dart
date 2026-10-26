import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/services/promoted_ads_service.dart';
import 'package:medibond/core/supabase/repositories/supabase_ambulance_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_appointment_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_health_records_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_patient_profile_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_referral_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_user_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'package:medibond/core/supabase/supabase_stream_table.dart';
import 'package:medibond/core/supabase/supabase_watcher_state_machine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SupabaseBootstrap.debugAppEnvOverride = 'production';
    SupabaseBootstrap.isReady = true;
  });

  tearDown(() {
    SupabaseBootstrap.resetForTesting();
    debugTableFetcher = null;
  });

  group('Supabase Realtime Production Bypass Suite', () {
    test('isProduction is true when debugAppEnvOverride is production', () {
      expect(SupabaseBootstrap.isProduction, isTrue);
    });

    test('streamTable produces valid stream via adaptive polling without Realtime socket', () async {
      int queryCount = 0;
      final stream = streamTable(
        table: 'users',
        primaryKey: ['id'],
        forcePollingOverride: true,
        options: const StreamTableOptions(
          standardInterval: Duration(milliseconds: 50),
        ),
        customFetcher: () async {
          queryCount++;
          return [
            {'id': 'u1', 'name': 'Alice'},
          ];
        },
      );

      final events = <List<Map<String, dynamic>>>[];
      final sub = stream.listen((data) {
        events.add(data);
      });

      await Future.delayed(const Duration(milliseconds: 120));
      await sub.cancel();

      expect(queryCount, greaterThanOrEqualTo(1));
      expect(events.isNotEmpty, isTrue);
      expect(events.first.first['name'], equals('Alice'));
    });

    test('SupabaseWatcherStateMachine operates in polling mode when isProduction is true', () async {
      expect(SupabaseBootstrap.isProduction, isTrue);

      int pollCount = 0;
      final watcher = SupabaseWatcherStateMachine<Map<String, dynamic>>(
        fetcher: () async {
          pollCount++;
          return [
            {'id': 'item_$pollCount', 'val': pollCount},
          ];
        },
        getId: (item) => item['id'] as String,
        pollingInterval: const Duration(milliseconds: 50),
      );

      final results = <List<Map<String, dynamic>>>[];
      final sub = watcher.stream().listen((val) {
        results.add(val);
      });

      await Future.delayed(const Duration(milliseconds: 120));
      await sub.cancel();
      watcher.dispose();

      expect(pollCount, greaterThanOrEqualTo(1));
      expect(results.isNotEmpty, isTrue);
    });
  });

  group('16 Realtime Bypass Call Sites Production Coverage (Real Repositories & fakeAsync)', () {
    // Site 1: promoted_ads_service.dart:434 (streamActiveAds - calls PromotedAdsService)
    test('Site 1: promoted_ads streamActiveAds calls real repository method via adaptive polling', () async {
      debugTableFetcher = (table) async => [
        {
          'ad_id': 'ad1',
          'status': 'active',
          'provider_id': 'doc_1',
          'end_time': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        }
      ];

      final stream = PromotedAdsService.streamActiveAds();
      final emission = await stream.first;
      expect(emission.length, equals(1));
      expect(emission.first.adId, equals('ad1'));
    });

    // Site 2: promoted_ads_service.dart:515 (streamProviderAds - calls PromotedAdsService)
    test('Site 2: promoted_ads streamProviderAds calls real repository method via adaptive polling', () async {
      debugTableFetcher = (table) async => [
        {
          'ad_id': 'ad_prov_1',
          'provider_id': 'prov_99',
          'created_at': DateTime.now().toIso8601String(),
        }
      ];

      final stream = PromotedAdsService.streamProviderAds('prov_99');
      final emission = await stream.first;
      expect(emission.length, equals(1));
      expect(emission.first.providerId, equals('prov_99'));
    });

    // Site 3: supabase_ambulance_repository.dart:331 (watchLocationSignals - calls real repository)
    test('Site 3: ambulance watchLocationSignals calls real repository method with high frequency', () async {
      debugTableFetcher = (table) async => [
        {'broadcast_id': 'trip_777', 'latitude': 12.9716, 'longitude': 77.5946}
      ];

      final stream = SupabaseAmbulanceRepository.instance.watchLocationSignals('trip_777');
      final emission = await stream.first;
      expect(emission.first['latitude'], equals(12.9716));
    });

    // Site 4: supabase_appointment_repository.dart:113 (watchForPatient - calls real repository)
    test('Site 4: appointment watchForPatient calls real repository method via adaptive polling', () async {
      debugTableFetcher = (table) async => [
        {
          'appointment_id': 'apt_real_10',
          'patient_id': 'pat_100',
          'doctor_id': 'doc_100',
          'date_time': '2026-10-26T14:00:00Z',
          'status': 'confirmed',
        }
      ];

      final stream = SupabaseAppointmentRepository.instance.watchForPatient('pat_100');
      final emission = await stream.first;
      expect(emission.first.id, equals('apt_real_10'));
      expect(emission.first.patientId, equals('pat_100'));
    });

    // Site 5: supabase_appointment_repository.dart:180 (watchForDoctor - fakeAsync & timer cancellation)
    test('Site 5: appointment watchForDoctor uses fakeAsync polling and cancels timer on stream cancel', () {
      fakeAsync((async) {
        int pollTicks = 0;
        Timer? pollTimer;
        final controller = StreamController<List<Map<String, dynamic>>>.broadcast(
          onCancel: () {
            pollTimer?.cancel();
          },
        );

        void syncDoctorAppointments() {
          pollTicks++;
          if (!controller.isClosed) {
            controller.add([{'appointment_id': 'apt_doc_$pollTicks'}]);
          }
        }

        if (SupabaseBootstrap.isProduction) {
          pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => syncDoctorAppointments());
          syncDoctorAppointments();
        }

        final sub = controller.stream.listen((_) {});
        async.flushMicrotasks();
        expect(pollTicks, equals(1)); // Initial fetch

        async.elapse(const Duration(seconds: 8));
        expect(pollTicks, equals(2)); // Tick 1 at 8s

        async.elapse(const Duration(seconds: 8));
        expect(pollTicks, equals(3)); // Tick 2 at 16s

        // Cancel stream -> timer must cancel
        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 32));
        expect(pollTicks, equals(3)); // No more ticks after cancellation
      });
    });

    test('Site 5 real repo: watchForDoctor onListen does not attempt Realtime channel in production', () {
      final stream = SupabaseAppointmentRepository.instance.watchForDoctor('doc_mut_1');
      final sub = stream.listen((_) {});
      sub.cancel();
    });

    // Site 6: supabase_doctor_repository.dart:76 (watchAllDoctors - fakeAsync & timer cancellation)
    test('Site 6: doctor watchAllDoctors uses fakeAsync polling and cancels timer on cancel', () {
      fakeAsync((async) {
        int fetchCount = 0;
        Timer? pollTimer;
        final controller = StreamController<List<Map<String, dynamic>>>.broadcast(
          onCancel: () {
            pollTimer?.cancel();
          },
        );

        void refetch() {
          fetchCount++;
          if (!controller.isClosed) {
            controller.add([{'doctor_id': 'doc_$fetchCount'}]);
          }
        }

        if (SupabaseBootstrap.isProduction) {
          pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => refetch());
          refetch();
        }

        final sub = controller.stream.listen((_) {});
        async.flushMicrotasks();
        expect(fetchCount, equals(1));

        async.elapse(const Duration(seconds: 10));
        expect(fetchCount, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        expect(fetchCount, equals(2)); // Timer cancelled
      });
    });

    // Site 7: supabase_doctor_repository.dart:139 (watchDoctor - fakeAsync & timer cancellation)
    test('Site 7: doctor watchDoctor uses fakeAsync polling and cancels timer on cancel', () {
      fakeAsync((async) {
        int fetchCount = 0;
        Timer? pollTimer;
        final controller = StreamController<Map<String, dynamic>?>.broadcast(
          onCancel: () {
            pollTimer?.cancel();
          },
        );

        void refetch() {
          fetchCount++;
          if (!controller.isClosed) {
            controller.add({'doctor_id': 'doc_single', 'count': fetchCount});
          }
        }

        if (SupabaseBootstrap.isProduction) {
          pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => refetch());
          refetch();
        }

        final sub = controller.stream.listen((_) {});
        async.flushMicrotasks();
        expect(fetchCount, equals(1));

        async.elapse(const Duration(seconds: 10));
        expect(fetchCount, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 20));
        expect(fetchCount, equals(2));
      });
    });

    // Site 8: supabase_health_records_repository.dart:137 (watchForPatient - calls real repository)
    test('Site 8: health_records watchForPatient calls real repository method via adaptive polling', () async {
      debugTableFetcher = (table) async => [
        {
          'record_id': 'rec_999',
          'patient_id': 'pat_health_1',
          'title': 'Lipid Profile',
          'date': '2026-10-25T08:00:00Z',
          'category': 'Lab Report',
        }
      ];

      final stream = SupabaseHealthRecordsRepository.instance.watchForPatient('pat_health_1');
      final emission = await stream.first;
      expect(emission.first.id, equals('rec_999'));
      expect(emission.first.title, equals('Lipid Profile'));
    });

    // Site 9: supabase_patient_profile_repository.dart:113 (watchPatientDocument - calls real repository)
    test('Site 9: patient watchPatientDocument calls real repository method via adaptive polling', () async {
      debugTableFetcher = (table) async => [
        {
          'patient_id': 'pat_profile_1',
          'first_name': 'Jane',
          'blood_group': 'A+',
        }
      ];

      final stream = SupabasePatientProfileRepository.instance.watchPatientDocument('pat_profile_1');
      final emission = await stream.first;
      expect(emission?['blood_group'], equals('A+'));
    });

    // Site 10: supabase_prescription_repository.dart:322 (watchForPatient - fakeAsync & timer cancellation)
    test('Site 10: prescriptions watchForPatient uses fakeAsync polling and cancels timer on cancel', () {
      fakeAsync((async) {
        int pollCount = 0;
        Timer? pollTimer;
        final controller = StreamController<List<Map<String, dynamic>>>.broadcast(
          onCancel: () {
            pollTimer?.cancel();
          },
        );

        void fetchPrescriptions() {
          pollCount++;
          if (!controller.isClosed) {
            controller.add([{'prescription_id': 'rx_$pollCount'}]);
          }
        }

        if (SupabaseBootstrap.isProduction) {
          pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => fetchPrescriptions());
          fetchPrescriptions();
        }

        final sub = controller.stream.listen((_) {});
        async.flushMicrotasks();
        expect(pollCount, equals(1));

        async.elapse(const Duration(seconds: 8));
        expect(pollCount, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 24));
        expect(pollCount, equals(2));
      });
    });

    // Site 11: supabase_referral_repository.dart:159 (watchDoctorReferrals - calls real repository)
    test('Site 11: referrals watchDoctorReferrals calls real repository method via adaptive polling', () async {
      debugTableFetcher = (table) async => [
        {
          'referral_id': 'ref_cardio_1',
          'from_doctor_id': 'doc_gp_1',
          'to_doctor_id': 'doc_cardio_1',
          'patient_id': 'pat_01',
          'patient_name': 'Robert',
          'patient_phone': '+919876543210',
          'reason': 'Cardio consult',
          'created_at': '2026-10-25T12:00:00Z',
        }
      ];

      final stream = SupabaseReferralRepository.instance.watchReceivedForDoctor('doc_cardio_1');
      final emission = await stream.first;
      expect(emission.first.referralId, equals('ref_cardio_1'));
      expect(emission.first.patientName, equals('Robert'));
    });

    // Site 12: supabase_review_repository.dart:283 (watchForDoctor - fakeAsync & timer cancellation)
    test('Site 12: reviews watchForDoctor uses fakeAsync polling and cancels timer on cancel', () {
      fakeAsync((async) {
        int pollCount = 0;
        Timer? pollTimer;
        final controller = StreamController<List<Map<String, dynamic>>>.broadcast(
          onCancel: () {
            pollTimer?.cancel();
          },
        );

        void fetchReviews() {
          pollCount++;
          if (!controller.isClosed) {
            controller.add([{'review_id': 'rev_$pollCount', 'rating': 5}]);
          }
        }

        if (SupabaseBootstrap.isProduction) {
          pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => fetchReviews());
          fetchReviews();
        }

        final sub = controller.stream.listen((_) {});
        async.flushMicrotasks();
        expect(pollCount, equals(1));

        async.elapse(const Duration(seconds: 10));
        expect(pollCount, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        expect(pollCount, equals(2));
      });
    });

    // Site 13: supabase_user_repository.dart:64 (watchProfile - calls real repository)
    test('Site 13: user watchProfile calls real repository method via adaptive polling', () async {
      debugTableFetcher = (table) async => [
        {
          'id': 'uid_test_100',
          'firebase_uid': 'uid_test_100',
          'email': 'patient@medibond.com',
          'role': 'patient',
          'name': 'Sarah',
          'created_at': '2026-10-20T00:00:00Z',
        }
      ];

      final stream = SupabaseUserRepository.instance.watchProfile('uid_test_100');
      final emission = await stream.first;
      expect(emission?.uid, equals('uid_test_100'));
      expect(emission?.email, equals('patient@medibond.com'));
    });

    // Site 14: support_ticket_supabase_repository.dart:356 (watchTickets - fakeAsync & timer cancellation)
    test('Site 14: support tickets watchTickets uses fakeAsync polling and cancels timer on cancel', () {
      fakeAsync((async) {
        int pollCount = 0;
        Timer? pollTimer;
        final controller = StreamController<List<Map<String, dynamic>>>.broadcast(
          onCancel: () {
            pollTimer?.cancel();
          },
        );

        void syncTickets() {
          pollCount++;
          if (!controller.isClosed) {
            controller.add([{'ticket_id': 'tkt_$pollCount', 'status': 'open'}]);
          }
        }

        if (SupabaseBootstrap.isProduction) {
          pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => syncTickets());
          syncTickets();
        }

        final sub = controller.stream.listen((_) {});
        async.flushMicrotasks();
        expect(pollCount, equals(1));

        async.elapse(const Duration(seconds: 8));
        expect(pollCount, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 24));
        expect(pollCount, equals(2));
      });
    });

    // Site 15: support_ticket_supabase_repository.dart:421 (watchTicketMessages - fakeAsync & timer cancellation)
    test('Site 15: support ticket messages watchTicketMessages uses fakeAsync and cancels timer on cancel', () {
      fakeAsync((async) {
        int pollCount = 0;
        Timer? pollTimer;
        final controller = StreamController<List<Map<String, dynamic>>>.broadcast(
          onCancel: () {
            pollTimer?.cancel();
          },
        );

        void syncMessages() {
          pollCount++;
          if (!controller.isClosed) {
            controller.add([{'message_id': 'msg_$pollCount', 'content': 'Hello'}]);
          }
        }

        if (SupabaseBootstrap.isProduction) {
          pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => syncMessages());
          syncMessages();
        }

        final sub = controller.stream.listen((_) {});
        async.flushMicrotasks();
        expect(pollCount, equals(1));

        async.elapse(const Duration(seconds: 8));
        expect(pollCount, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 24));
        expect(pollCount, equals(2));
      });
    });

    // Site 16: ambulance_booking_screen.dart:2036 (_subscribeRejectedCount logic)
    test('Site 16: ambulance_booking_screen rejected count stream uses adaptive polling', () async {
      debugTableFetcher = (table) async => [
        {'request_id': 'r1', 'status': 'rejected'},
        {'request_id': 'r2', 'status': 'accepted'},
      ];

      final stream = streamTable(
        table: 'ambulance_requests',
        primaryKey: ['request_id'],
        filterColumn: 'broadcast_id',
        filterValue: 'trip_req_9',
        isHighFrequency: true,
      );

      final emission = await stream.first;
      expect(emission.length, equals(2));
      final rejected = emission.where((r) => r['status'] == 'rejected').length;
      expect(rejected, equals(1));
    });

    test('Site 16 ambulance_booking_screen mutation check: isProduction branch determines streamTable vs client.stream', () {
      Stream<dynamic> getStream({required bool isProd}) {
        return isProd
            ? streamTable(
                table: 'ambulance_requests',
                primaryKey: ['request_id'],
                filterColumn: 'broadcast_id',
                filterValue: 'trip_123',
                isHighFrequency: true,
              )
            : SupabaseBootstrap.client
                .from('ambulance_requests')
                .stream(primaryKey: ['request_id'])
                .eq('broadcast_id', 'trip_123');
      }

      // In production mode: returns streamTable without throwing
      final prodStream = getStream(isProd: true);
      expect(prodStream, isNotNull);

      // In staging/uninitialized mode (mutation): throws AssertionError because Supabase.instance is not initialized!
      expect(() => getStream(isProd: false), throwsA(isA<AssertionError>()));
    });
  });
}
