import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/firebase/models/doctor_lab_order.dart';
import 'package:medibond/core/firebase/repositories/lab_booking_repository.dart';
import 'package:medibond/core/supabase/mappers/ambulance_supabase_mapper.dart';
import 'package:medibond/core/supabase/mappers/lab_supabase_mapper.dart';
import 'package:medibond/core/supabase/mappers/pharmacy_supabase_mapper.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'package:medibond/core/supabase/supabase_watcher_state_machine.dart';
import 'package:medibond/features/ambulance/models/ambulance_models.dart';
import 'package:medibond/features/lab/models/lab_connection_models.dart';
import 'package:medibond/features/pharmacy/models/pharmacy_models.dart';

void main() {
  setUp(() {
    SupabaseBootstrap.resetForTesting();
  });

  group('SupabaseWatcherStateMachine (Real State Machine Verification)', () {
    test('1. Error surfacing: fetcher exception is emitted to stream', () async {
      final stateMachine = SupabaseWatcherStateMachine<Map<String, dynamic>>(
        fetcher: () async => throw StateError('Database connection lost'),
        getId: (item) => item['id'] as String,
      );

      final stream = stateMachine.stream();
      expect(
        stream,
        emitsError(isA<StateError>().having((e) => e.message, 'message', contains('Database connection lost'))),
      );
    });

    test('2. Resync replaces cache authoritatively', () async {
      int fetchCount = 0;
      final stateMachine = SupabaseWatcherStateMachine<Map<String, dynamic>>(
        fetcher: () async {
          fetchCount++;
          if (fetchCount == 1) {
            return [
              {'id': '1', 'name': 'First Item'},
            ];
          } else {
            return [
              {'id': '2', 'name': 'Second Item'},
            ];
          }
        },
        getId: (item) => item['id'] as String,
      );

      final stream = stateMachine.stream();

      expect(
        stream,
        emitsInOrder([
          [
            {'id': '1', 'name': 'First Item'},
          ],
          [
            {'id': '2', 'name': 'Second Item'},
          ],
        ]),
      );

      // Wait for initial listen + fetch
      await pumpEventQueue();
      // Trigger authorative resync
      await stateMachine.resync();
    });

    test('3. Delete removes row and emits revised cache', () async {
      final eventController = StreamController<WatcherEvent<Map<String, dynamic>>>();
      final stateMachine = SupabaseWatcherStateMachine<Map<String, dynamic>>(
        fetcher: () async => [
          {'id': 'item_a', 'val': 10},
          {'id': 'item_b', 'val': 20},
        ],
        getId: (item) => item['id'] as String,
        eventStream: eventController.stream,
      );

      final stream = stateMachine.stream();

      expect(
        stream,
        emitsInOrder([
          [
            {'id': 'item_a', 'val': 10},
            {'id': 'item_b', 'val': 20},
          ],
          [
            {'id': 'item_b', 'val': 20},
          ],
        ]),
      );

      await pumpEventQueue();
      // Incremental delete of item_a
      eventController.add(const WatcherEvent.delete('item_a'));
      await pumpEventQueue();
      await eventController.close();
      stateMachine.dispose();
    });

    test('4. Reconnect triggers authorative resync', () async {
      final eventController = StreamController<WatcherEvent<Map<String, dynamic>>>();
      var currentItems = [
        {'id': 'x', 'status': 'pending'},
      ];

      final stateMachine = SupabaseWatcherStateMachine<Map<String, dynamic>>(
        fetcher: () async => List.from(currentItems),
        getId: (item) => item['id'] as String,
        eventStream: eventController.stream,
      );

      final stream = stateMachine.stream();

      expect(
        stream,
        emitsInOrder([
          [
            {'id': 'x', 'status': 'pending'},
          ],
          [
            {'id': 'x', 'status': 'connected'},
          ],
        ]),
      );

      await pumpEventQueue();
      currentItems = [
        {'id': 'x', 'status': 'connected'},
      ];
      // Simulate network reconnect event
      eventController.add(const WatcherEvent.resync());
      await pumpEventQueue();
      await eventController.close();
      stateMachine.dispose();
    });

    test('5. Late listener immediately gets cached list', () async {
      final stateMachine = SupabaseWatcherStateMachine<Map<String, dynamic>>(
        fetcher: () async => [
          {'id': 'entry_1', 'title': 'Active Booking'},
        ],
        getId: (item) => item['id'] as String,
      );

      final stream1 = stateMachine.stream();
      await expectLater(
        stream1,
        emits([
          {'id': 'entry_1', 'title': 'Active Booking'},
        ]),
      );

      // Late listener subscribes after initial sync completed
      final stream2 = stateMachine.stream();
      final lateEmitted = await stream2.first;
      expect(lateEmitted, hasLength(1));
      expect(lateEmitted.first['id'], 'entry_1');
      stateMachine.dispose();
    });
  });

  group('PharmacySupabaseMapper (Row <-> Model)', () {
    test('Maps medical store row to MedicalStoreProfile and back', () {
      final row = {
        'store_id': 'store_001',
        'store_name': 'Apollo Pharmacy',
        'license_number': 'DL-AP-102938',
        'city': 'Bengaluru',
        'address_line': '12 Brigade Road',
        'phone': '9876543210',
        'verified': true,
        'metadata': {
          'owner_name': 'Ramesh Kumar',
          'email': 'apollo.brigade@example.com',
          'gstNumber': '29ABCDE1234F1Z5',
        },
      };

      final profile = PharmacySupabaseMapper.storeFromRow(row);
      expect(profile.id, 'store_001');
      expect(profile.storeName, 'Apollo Pharmacy');
      expect(profile.city, 'Bengaluru');
      expect(profile.verified, isTrue);

      final backToRow = PharmacySupabaseMapper.storeToRow(profile, ownerUid: 'user_pharm_01');
      expect(backToRow['store_id'], 'store_001');
      expect(backToRow['owner_uid'], 'user_pharm_01');
      expect(backToRow['city'], 'Bengaluru');
      expect(backToRow['verified'], isTrue);
    });

    test('Maps pharmacy delivery row to PharmacyPrescriptionDelivery and back', () {
      final now = DateTime.now().toUtc();
      final row = {
        'delivery_id': 'del_777',
        'prescription_id': 'rx_888',
        'doctor_id': 'doc_999',
        'doctor_name': 'Dr. Sharma',
        'store_id': 'store_001',
        'store_name': 'Apollo Pharmacy',
        'patient_id': 'pat_111',
        'patient_name': 'Rahul Verma',
        'status': 'viewed',
        'sent_at': now.toIso8601String(),
        'dispensing_notes': 'Substitute suggested',
        'pharmacy_delivery_medicines': [
          {
            'medicine_entry_id': 'med_1',
            'medicine_name': 'Paracetamol 500mg',
            'dosage_label': '1 tablet',
            'form': 'Tablet',
            'quantity': '10',
            'frequency_label': 'Twice daily',
            'duration_label': '5 days',
            'availability': 'in_stock',
            'substitute_name': '',
          }
        ],
      };

      final delivery = PharmacySupabaseMapper.deliveryFromRow(row);
      expect(delivery, isNotNull);
      expect(delivery!.id, 'del_777');
      expect(delivery.status, PharmacyDeliveryStatus.viewed);
      expect(delivery.medicineLines, hasLength(1));
      expect(delivery.medicineLines.first.availability, MedicineAvailability.available);

      final payload = PharmacySupabaseMapper.deliveryToRow(delivery);
      expect(payload['delivery_id'], 'del_777');
      expect(payload['status'], 'viewed');
      expect(payload['dispensing_notes'], 'Substitute suggested');
    });

    test('Maps pharmacy connection row to PharmacyConnection and back', () {
      final now = DateTime.now().toUtc();
      final row = {
        'connection_id': 'conn_100',
        'doctor_id': 'doc_999',
        'doctor_name': 'Dr. Sharma',
        'store_id': 'store_001',
        'store_name': 'Apollo Pharmacy',
        'status': 'active',
        'requested_by': 'doctor',
        'requested_at': now.toIso8601String(),
        'responded_at': now.add(const Duration(minutes: 5)).toIso8601String(),
      };

      final conn = PharmacySupabaseMapper.connectionFromRow(row);
      expect(conn, isNotNull);
      expect(conn!.id, 'conn_100');
      expect(conn.status, ConnectionStatus.active);
      expect(conn.requestedBy, ConnectionRequester.doctor);

      final payload = PharmacySupabaseMapper.connectionToRow(conn);
      expect(payload['connection_id'], 'conn_100');
      expect(payload['status'], 'active');
      expect(payload['requested_by'], 'doctor');
    });
  });

  group('LabSupabaseMapper (Row <-> Model)', () {
    test('Maps lab booking row to LabBookingRecord and back', () {
      final now = DateTime.now().toUtc();
      final row = {
        'booking_id': 'bkg_500',
        'lab_id': 'lab_001',
        'lab_name': 'Thyrocare Lab',
        'patient_id': 'pat_111',
        'patient_name': 'Rahul Verma',
        'test_name': 'Complete Blood Count (CBC)',
        'date_time': now.toIso8601String(),
        'slot_label': '09:00 AM',
        'is_home_collection': true,
        'collection_address': 'Flat 402, Sunshine Apts',
        'status': 'confirmed',
        'report_s3_key': 'reports/labs/bkg_500.pdf',
      };

      final record = LabSupabaseMapper.bookingFromRow(row);
      expect(record, isNotNull);
      expect(record!.bookingId, 'bkg_500');
      expect(record.collectionType, 'home');
      expect(record.reportStorageKey, 'reports/labs/bkg_500.pdf');

      final payload = LabSupabaseMapper.bookingToRow(record);
      expect(payload['booking_id'], 'bkg_500');
      expect(payload['is_home_collection'], isTrue);
      expect(payload['report_s3_key'], 'reports/labs/bkg_500.pdf');
    });

    test('Maps lab order row to DoctorLabOrder and back', () {
      final now = DateTime.now().toUtc();
      final row = {
        'order_id': 'ord_600',
        'doctor_id': 'doc_999',
        'doctor_name': 'Dr. Sharma',
        'patient_id': 'pat_111',
        'patient_name': 'Rahul Verma',
        'patient_age': 35,
        'lab_id': 'lab_001',
        'lab_name': 'Thyrocare Lab',
        'test_ids': ['t_cbc', 't_lft'],
        'test_names': ['CBC', 'Liver Function Test'],
        'clinical_notes': 'Fasting required 10 hrs',
        'status': 'prescribed',
        'created_at': now.toIso8601String(),
      };

      final order = LabSupabaseMapper.orderFromRow(row);
      expect(order, isNotNull);
      expect(order!.orderId, 'ord_600');
      expect(order.testNames, contains('CBC'));

      final payload = LabSupabaseMapper.orderToRow(order);
      expect(payload['order_id'], 'ord_600');
      expect(payload['clinical_notes'], 'Fasting required 10 hrs');
    });
  });

  group('AmbulanceSupabaseMapper (Row <-> Model)', () {
    test('Maps ambulance driver row to RegisteredAmbulance and back', () {
      final row = {
        'ambulance_id': 'amb_001',
        'driver_name': 'Suresh Kumar',
        'vehicle_number': 'KA-01-EA-1234',
        'phone': '9876543210',
        'city': 'Bengaluru',
        'is_available': true,
        'verified': true,
        'rating': 4.8,
        'rating_count': 25,
        'metadata': {
          'service_name': 'FastCare Ambulance',
          'owner_name': 'Suresh Kumar',
        },
      };

      final driver = AmbulanceSupabaseMapper.driverFromRow(row);
      expect(driver.id, 'amb_001');
      expect(driver.driverName, 'Suresh Kumar');
      expect(driver.available, isTrue);
      expect(driver.averageRating, closeTo(4.8, 0.05));

      final payload = AmbulanceSupabaseMapper.driverToRow(driver, ownerUid: 'user_driver_01');
      expect(payload['ambulance_id'], 'amb_001');
      expect(payload['vehicle_number'], 'KA-01-EA-1234');
      expect(payload['owner_uid'], 'user_driver_01');
    });

    test('Maps ambulance broadcast row to AmbulanceBooking and back', () {
      final now = DateTime.now().toUtc();
      final row = {
        'broadcast_id': 'bcast_300',
        'patient_id': 'pat_111',
        'patient_name': 'Priya Singh',
        'patient_phone': '9988776655',
        'pickup_address': 'MG Road Metro Station',
        'destination_address': 'Manipal Hospital',
        'status': 'accepted',
        'assigned_driver_id': 'amb_001',
        'created_at': now.toIso8601String(),
      };

      final booking = AmbulanceSupabaseMapper.bookingFromRow(row);
      expect(booking, isNotNull);
      expect(booking!.id, 'bcast_300');
      expect(booking.status, AmbulanceBookingStatus.accepted);
      expect(booking.acceptedAmbulanceId, 'amb_001');

      final payload = AmbulanceSupabaseMapper.bookingToRow(booking);
      expect(payload['broadcast_id'], 'bcast_300');
      expect(payload['status'], 'accepted');
      expect(payload['assigned_driver_id'], 'amb_001');
    });
  });
}
