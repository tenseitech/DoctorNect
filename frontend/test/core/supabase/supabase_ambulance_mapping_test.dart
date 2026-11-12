import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/supabase/mappers/ambulance_supabase_mapper.dart';
import 'package:medibond/features/ambulance/models/ambulance_models.dart';

void main() {
  group('AmbulanceSupabaseMapper Schema Alignment & Status Mapping Tests', () {
    test('bookingFromRow correctly maps real Postgres schema columns', () {
      final row = {
        'broadcast_id': 'bcast-456',
        'patient_id': 'pat-123',
        'patient_name': 'John Doe',
        'pickup_location': '123 Main St, Pune',
        'drop_location': 'City Hospital, Pune',
        'contact_phone': '+919876543210',
        'status': 'accepted',
        'accepted_driver_id': 'driver-789',
        'created_at': '2026-10-26T10:00:00.000Z',
      };

      final booking = AmbulanceSupabaseMapper.bookingFromRow(row);
      expect(booking, isNotNull);
      expect(booking!.id, equals('bcast-456'));
      expect(booking.bookedById, equals('pat-123'));
      expect(booking.patientName, equals('John Doe'));
      expect(booking.pickupLocation, equals('123 Main St, Pune'));
      expect(booking.contactPhone, equals('+919876543210'));
      expect(booking.status, equals(AmbulanceBookingStatus.accepted));
      expect(booking.acceptedAmbulanceId, equals('driver-789'));
    });

    test('bookingFromRow maps all status variants correctly', () {
      final statuses = {
        'pending': AmbulanceBookingStatus.pending,
        'accepted': AmbulanceBookingStatus.accepted,
        'in_progress': AmbulanceBookingStatus.accepted,
        'dispatched': AmbulanceBookingStatus.accepted,
        'completed': AmbulanceBookingStatus.completed,
        'cancelled': AmbulanceBookingStatus.cancelled,
        'unknown_status': AmbulanceBookingStatus.pending,
      };

      for (final entry in statuses.entries) {
        final row = {
          'broadcast_id': 'bcast-status-${entry.key}',
          'patient_id': 'pat-1',
          'patient_name': 'Test',
          'pickup_location': 'Loc',
          'status': entry.key,
          'created_at': '2026-10-26T10:00:00.000Z',
        };
        final booking = AmbulanceSupabaseMapper.bookingFromRow(row);
        expect(booking, isNotNull);
        expect(booking!.status, equals(entry.value),
            reason: 'Status "${entry.key}" should map to ${entry.value}');
      }
    });

    test('bookingFromRow supports backwards compatibility for legacy column names', () {
      final legacyRow = {
        'broadcast_id': 'bcast-legacy',
        'patient_id': 'pat-1',
        'patient_name': 'Legacy Patient',
        'pickup_address': 'Legacy Pickup',
        'destination_address': 'Legacy Destination',
        'patient_phone': '+919999988888',
        'status': 'completed',
        'assigned_driver_id': 'legacy-driver',
        'created_at': '2026-10-26T10:00:00.000Z',
      };

      final booking = AmbulanceSupabaseMapper.bookingFromRow(legacyRow);
      expect(booking, isNotNull);
      expect(booking!.pickupLocation, equals('Legacy Pickup'));
      expect(booking.contactPhone, equals('+919999988888'));
      expect(booking.acceptedAmbulanceId, equals('legacy-driver'));
      expect(booking.status, equals(AmbulanceBookingStatus.completed));
    });

    test('bookingToRow outputs verified Postgres schema columns (no invalid columns)', () {
      final booking = AmbulanceBooking(
        id: 'bcast-out-1',
        patientName: 'Jane Doe',
        pickupLocation: 'Shivaji Nagar, Pune',
        contactPhone: '+919123456789',
        bookedByRole: AmbulanceBookedByRole.patient,
        bookedByName: 'Jane Doe',
        bookedById: 'pat-999',
        createdAt: DateTime(2026, 10, 26, 12, 0),
        status: AmbulanceBookingStatus.accepted,
        acceptedAmbulanceId: 'driver-555',
      );

      final row = AmbulanceSupabaseMapper.bookingToRow(
        booking,
        destinationAddress: 'Ruby Hall Clinic',
      );

      expect(row['broadcast_id'], equals('bcast-out-1'));
      expect(row['patient_id'], equals('pat-999'));
      expect(row['patient_name'], equals('Jane Doe'));
      expect(row['pickup_location'], equals('Shivaji Nagar, Pune'));
      expect(row['drop_location'], equals('Ruby Hall Clinic'));
      expect(row['contact_phone'], equals('+919123456789'));
      expect(row['status'], equals('accepted'));
      expect(row['accepted_driver_id'], equals('driver-555'));

      // Ensure invalid columns that caused schema mismatch errors are NOT emitted
      expect(row.containsKey('pickup_address'), isFalse);
      expect(row.containsKey('destination_address'), isFalse);
      expect(row.containsKey('patient_phone'), isFalse);
      expect(row.containsKey('assigned_driver_id'), isFalse);
    });

    test('requestFromRow correctly maps request and nested broadcast columns', () {
      final row = {
        'request_id': 'req-101',
        'driver_id': 'driver-202',
        'patient_id': 'pat-303',
        'pickup_location': 'Sector 14',
        'drop_location': 'General Hospital',
        'contact_phone': '+919876543210',
        'status': 'accepted',
        'created_at': '2026-10-26T11:00:00.000Z',
      };

      final req = AmbulanceSupabaseMapper.requestFromRow(row);
      expect(req, isNotNull);
      expect(req!.id, equals('req-101'));
      expect(req.driverId, equals('driver-202'));
      expect(req.patientId, equals('pat-303'));
      expect(req.pickupLocation, equals('Sector 14'));
      expect(req.dropLocation, equals('General Hospital'));
      expect(req.status, equals(AmbulanceRequestStatus.accepted));
    });

    test('requestFromRow maps all request status variants', () {
      final requestStatuses = {
        'pending': AmbulanceRequestStatus.pending,
        'accepted': AmbulanceRequestStatus.accepted,
        'cancelled': AmbulanceRequestStatus.cancelled,
        'rejected': AmbulanceRequestStatus.cancelled,
        'taken': AmbulanceRequestStatus.cancelled,
      };

      for (final entry in requestStatuses.entries) {
        final row = {
          'request_id': 'req-status-${entry.key}',
          'driver_id': 'driver-1',
          'patient_id': 'pat-1',
          'status': entry.key,
          'created_at': '2026-10-26T11:00:00.000Z',
        };
        final req = AmbulanceSupabaseMapper.requestFromRow(row);
        expect(req, isNotNull);
        expect(req!.status, equals(entry.value),
            reason: 'Request status "${entry.key}" should map to ${entry.value}');
      }
    });
  });
}
