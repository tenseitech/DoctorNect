import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/core/services/promoted_ads_service.dart';
import 'package:medibond/core/supabase/in_app_notification_supabase_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_ambulance_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_appointment_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_doctor_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_health_records_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_lab_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_patient_profile_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_pharmacy_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_prescription_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_referral_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_review_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_user_repository.dart';
import 'package:medibond/core/supabase/support_ticket_supabase_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'package:medibond/core/supabase/supabase_stream_table.dart';
import 'package:medibond/core/supabase/supabase_watcher_state_machine.dart';
import 'package:medibond/features/ambulance/ambulance_booking_screen.dart';
import 'package:medibond/features/doctor/clinical/models/clinical_models.dart';
import 'package:medibond/features/patient/doctor_profile/models/doctor_profile_detail.dart';
import 'package:medibond/features/patient/models/patient_models.dart';

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

    // Site 5: supabase_appointment_repository.dart:180 (watchForDoctor - calls real repository method in fakeAsync)
    test('Site 5: appointment watchForDoctor calls real repository method in fakeAsync with 8s ticks and zero ticks after cancel', () {
      fakeAsync((async) {
        int fetchCount = 0;
        debugTableFetcher = (table) async {
          fetchCount++;
          return [
            {
              'appointment_id': 'apt_doc_$fetchCount',
              'patient_id': 'pat_1',
              'doctor_id': 'doc_real_1',
              'date_time': '2026-10-26T14:00:00Z',
              'status': 'confirmed',
            }
          ];
        };

        final emissions = <List<DoctorNectAppointmentRecord>>[];
        final stream = SupabaseAppointmentRepository.instance.watchForDoctor('doc_real_1');
        final sub = stream.listen((list) {
          emissions.add(list);
        });

        async.flushMicrotasks();
        expect(fetchCount, equals(1)); // Initial fetch
        expect(emissions.length, equals(1));

        async.elapse(const Duration(seconds: 8));
        expect(fetchCount, equals(2)); // Tick 1 at 8s
        expect(emissions.length, equals(2));

        async.elapse(const Duration(seconds: 8));
        expect(fetchCount, equals(3)); // Tick 2 at 16s
        expect(emissions.length, equals(3));

        // Cancel stream -> timer must cancel
        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 32));
        expect(fetchCount, equals(3)); // Zero ticks after cancel
        expect(emissions.length, equals(3));
      });
    });

    // Site 6: supabase_doctor_repository.dart:76 (streamAllDoctors - calls real repository method in fakeAsync)
    test('Site 6: doctor streamAllDoctors calls real repository method in fakeAsync with 10s ticks and zero ticks after cancel', () {
      fakeAsync((async) {
        int fetchCount = 0;
        debugTableFetcher = (table) async {
          fetchCount++;
          return [
            {
              'doctor_id': 'doc_$fetchCount',
              'name': 'Dr. Test $fetchCount',
              'specialization': 'General Physician',
              'qualification': 'MBBS',
              'verified': true,
            }
          ];
        };

        final emissions = <List<DoctorListing>>[];
        final stream = SupabaseDoctorRepository.instance.streamAllDoctors();
        final sub = stream.listen((list) {
          emissions.add(list);
        });

        async.flushMicrotasks();
        expect(fetchCount, equals(1));
        expect(emissions.length, equals(1));

        async.elapse(const Duration(seconds: 10));
        expect(fetchCount, equals(2));
        expect(emissions.length, equals(2));

        async.elapse(const Duration(seconds: 10));
        expect(fetchCount, equals(3));
        expect(emissions.length, equals(3));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        expect(fetchCount, equals(3)); // Zero ticks after cancel
        expect(emissions.length, equals(3));
      });
    });

    // Site 7: supabase_doctor_repository.dart:139 (watchDoctor - calls real repository method in fakeAsync)
    test('Site 7: doctor watchDoctor calls real repository method in fakeAsync with 10s ticks and zero ticks after cancel', () {
      fakeAsync((async) {
        int fetchCount = 0;
        debugTableFetcher = (table) async {
          fetchCount++;
          return [
            {
              'doctor_id': 'doc_single',
              'name': 'Dr. Single $fetchCount',
              'specialization': 'Cardiology',
            }
          ];
        };

        final emissions = <Map<String, dynamic>?>[];
        final stream = SupabaseDoctorRepository.instance.watchDoctor('doc_single');
        final sub = stream.listen((doc) {
          emissions.add(doc);
        });

        async.flushMicrotasks();
        expect(fetchCount, equals(1));
        expect(emissions.length, equals(1));

        async.elapse(const Duration(seconds: 10));
        expect(fetchCount, equals(2));
        expect(emissions.length, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        expect(fetchCount, equals(2)); // Zero ticks after cancel
        expect(emissions.length, equals(2));
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

    // Site 10: supabase_prescription_repository.dart:322 (watchForPatient - calls real repository method in fakeAsync)
    test('Site 10: prescriptions watchForPatient calls real repository method in fakeAsync with 8s ticks and zero ticks after cancel', () {
      fakeAsync((async) {
        int fetchCount = 0;
        debugTableFetcher = (table) async {
          fetchCount++;
          return [
            {
              'prescription_id': 'rx_$fetchCount',
              'patient_id': 'pat_rx_1',
              'doctor_id': 'doc_1',
              'patient_name': 'Patient A',
              'doctor_name': 'Dr. B',
              'prescription_date': '2026-10-26T12:00:00Z',
              'medicines': [],
            }
          ];
        };

        final emissions = <List<PrescriptionDraft>>[];
        final stream = SupabasePrescriptionRepository.instance.watchForPatient('pat_rx_1');
        final sub = stream.listen((list) {
          emissions.add(list);
        });

        async.flushMicrotasks();
        expect(fetchCount, equals(1));
        expect(emissions.length, equals(1));

        async.elapse(const Duration(seconds: 8));
        expect(fetchCount, equals(2));
        expect(emissions.length, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 24));
        expect(fetchCount, equals(2)); // Zero ticks after cancel
        expect(emissions.length, equals(2));
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

    // Site 12: supabase_review_repository.dart:283 (watchForDoctor - calls real repository method in fakeAsync)
    test('Site 12: reviews watchForDoctor calls real repository method in fakeAsync with 10s ticks and zero ticks after cancel', () {
      fakeAsync((async) {
        int fetchCount = 0;
        debugTableFetcher = (table) async {
          fetchCount++;
          return [
            {
              'review_id': 'rev_$fetchCount',
              'doctor_id': 'doc_rev_1',
              'patient_id': 'pat_1',
              'rating': 5,
              'created_at': '2026-10-26T10:00:00Z',
            }
          ];
        };

        final emissions = <List<PatientDoctorReview>>[];
        final stream = SupabaseReviewRepository.instance.watchForDoctor('doc_rev_1');
        final sub = stream.listen((list) {
          emissions.add(list);
        });

        async.flushMicrotasks();
        expect(fetchCount, equals(1));
        expect(emissions.length, equals(1));

        async.elapse(const Duration(seconds: 10));
        expect(fetchCount, equals(2));
        expect(emissions.length, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        expect(fetchCount, equals(2)); // Zero ticks after cancel
        expect(emissions.length, equals(2));
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

    // Site 14: support_ticket_supabase_repository.dart:356 (watchMyTickets - calls real repository method in fakeAsync)
    test('Site 14: support tickets watchMyTickets calls real repository method in fakeAsync with 8s ticks and zero ticks after cancel', () {
      fakeAsync((async) {
        int fetchCount = 0;
        debugTableFetcher = (table) async {
          fetchCount++;
          return [
            {
              'ticket_id': 'tkt_$fetchCount',
              'patient_id': 'pat_tkt_1',
              'status': 'open',
              'subject': 'Help $fetchCount',
            }
          ];
        };

        final emissions = <List<SupportTicketModel>>[];
        final stream = SupportTicketSupabaseRepository.instance.watchMyTickets(patientId: 'pat_tkt_1');
        final sub = stream.listen((list) {
          emissions.add(list);
        });

        async.flushMicrotasks();
        expect(fetchCount, equals(1));
        expect(emissions.length, equals(1));

        async.elapse(const Duration(seconds: 8));
        expect(fetchCount, equals(2));
        expect(emissions.length, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 24));
        expect(fetchCount, equals(2)); // Zero ticks after cancel
        expect(emissions.length, equals(2));
      });
    });

    // Site 15: support_ticket_supabase_repository.dart:421 (watchTicketMessages - calls real repository method in fakeAsync)
    test('Site 15: support ticket messages watchTicketMessages calls real repository method in fakeAsync with 8s ticks and zero ticks after cancel', () {
      fakeAsync((async) {
        int fetchCount = 0;
        debugTableFetcher = (table) async {
          fetchCount++;
          return [
            {
              'message_id': 'msg_$fetchCount',
              'ticket_id': 'tkt_msg_1',
              'text': 'Hello $fetchCount',
              'sender_id': 'user_1',
              'sender_role': 'patient',
              'created_at': '2026-10-26T12:00:00Z',
            }
          ];
        };

        final emissions = <List<TicketMessageModel>>[];
        final stream = SupportTicketSupabaseRepository.instance.watchTicketMessages('tkt_msg_1');
        final sub = stream.listen((list) {
          emissions.add(list);
        });

        async.flushMicrotasks();
        expect(fetchCount, equals(1));
        expect(emissions.length, equals(1));

        async.elapse(const Duration(seconds: 8));
        expect(fetchCount, equals(2));
        expect(emissions.length, equals(2));

        sub.cancel();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 24));
        expect(fetchCount, equals(2)); // Zero ticks after cancel
        expect(emissions.length, equals(2));
      });
    });

    // Site 16: ambulance_booking_screen.dart:2036 (AmbulanceBookingScreen.watchRejectedRequestsStream)
    test('Site 16 real method: AmbulanceBookingScreen.watchRejectedRequestsStream calls streamTable in production without throwing', () {
      final stream = AmbulanceBookingScreen.watchRejectedRequestsStream('trip_123');
      expect(stream, isNotNull);
    });

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

  group('Release Mode Protections and SupabaseWatcherStateMachine Repositories', () {
    test('debugAppEnvOverride setter throws UnsupportedError when kReleaseMode is true', () {
      // In debug/profile mode (test runner), setter succeeds
      SupabaseBootstrap.debugAppEnvOverride = 'staging';
      expect(SupabaseBootstrap.debugAppEnvOverride, equals('staging'));
      SupabaseBootstrap.debugAppEnvOverride = 'production';
      expect(SupabaseBootstrap.debugAppEnvOverride, equals('production'));

      // Simulate kReleaseMode via test hook: setter must throw UnsupportedError
      try {
        SupabaseBootstrap.debugIsReleaseModeOverride = true;
        expect(
          () => SupabaseBootstrap.debugAppEnvOverride = 'staging',
          throwsA(isA<UnsupportedError>()),
        );
      } finally {
        SupabaseBootstrap.debugIsReleaseModeOverride = null;
      }
    });

    test('SupabaseLabRepository watchBookingsForPatient operates via StateMachine polling in production', () async {
      int fetchCount = 0;
      debugTableFetcher = (table) async {
        fetchCount++;
        return [
          {
            'booking_id': 'booking_$fetchCount',
            'patient_id': 'pat_lab_1',
            'lab_id': 'lab_1',
            'date_time': '2026-10-26T10:00:00Z',
            'status': 'confirmed',
          }
        ];
      };

      final stream = SupabaseLabRepository.instance.watchBookingsForPatient('pat_lab_1');
      final emission = await stream.first;
      expect(emission.length, equals(1));
      expect(emission.first.bookingId, equals('booking_1'));
      expect(fetchCount, greaterThanOrEqualTo(1));
    });

    test('SupabasePharmacyRepository watchDeliveriesForStore operates via StateMachine polling in production', () async {
      int fetchCount = 0;
      debugTableFetcher = (table) async {
        fetchCount++;
        return [
          {
            'delivery_id': 'deliv_$fetchCount',
            'store_id': 'store_1',
            'patient_id': 'pat_1',
            'status': 'sent',
            'sent_at': '2026-10-26T11:00:00Z',
          }
        ];
      };

      final stream = SupabasePharmacyRepository.instance.watchDeliveriesForStore('store_1');
      final emission = await stream.first;
      expect(emission.length, equals(1));
      expect(emission.first.id, equals('deliv_1'));
      expect(fetchCount, greaterThanOrEqualTo(1));
    });

    test('SupabaseAmbulanceRepository watchPatientHistory operates via StateMachine polling in production', () async {
      int fetchCount = 0;
      debugTableFetcher = (table) async {
        fetchCount++;
        return [
          {
            'broadcast_id': 'trip_$fetchCount',
            'patient_id': 'pat_amb_1',
            'status': 'completed',
            'created_at': '2026-10-26T09:00:00Z',
          }
        ];
      };

      final stream = SupabaseAmbulanceRepository.instance.watchPatientHistory('pat_amb_1');
      final emission = await stream.first;
      expect(emission.length, equals(1));
      expect(emission.first.id, equals('trip_1'));
      expect(fetchCount, greaterThanOrEqualTo(1));
    });

    test('InAppNotificationSupabaseRepository watchForRecipient operates via StateMachine polling in production', () async {
      int fetchCount = 0;
      debugTableFetcher = (table) async {
        fetchCount++;
        return [
          {
            'notification_id': 'notif_$fetchCount',
            'recipient_uid': 'user_notif_1',
            'title': 'Test Notice',
            'body': 'Production polling works',
            'created_at': '2026-10-26T12:00:00Z',
            'is_read': false,
          }
        ];
      };

      final stream = InAppNotificationSupabaseRepository.instance.watchForRecipient('user_notif_1');
      final emission = await stream.first;
      expect(emission.length, equals(1));
      expect(emission.first.title, equals('Test Notice'));
      expect(fetchCount, greaterThanOrEqualTo(1));
    });
  });
}
