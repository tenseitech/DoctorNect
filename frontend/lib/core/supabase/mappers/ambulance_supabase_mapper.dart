import '../../../features/ambulance/models/ambulance_models.dart';

abstract final class AmbulanceSupabaseMapper {
  static RegisteredAmbulance driverFromRow(Map<String, dynamic> row) {
    final meta = (row['metadata'] as Map<String, dynamic>?) ?? const {};
    final rating = (row['rating'] as num?)?.toDouble() ?? 0.0;
    final ratingCount = row['rating_count'] as int? ?? 0;

    return RegisteredAmbulance(
      id: row['ambulance_id'] as String? ?? '',
      serviceName: meta['service_name'] as String? ?? 'Ambulance Service',
      driverName: row['driver_name'] as String? ?? 'Driver',
      phone: row['phone'] as String? ?? '',
      vehicleNumber: row['vehicle_number'] as String? ?? '',
      city: row['city'] as String? ?? '',
      available: row['is_available'] as bool? ?? true,
      verified: row['verified'] as bool? ?? false,
      totalRating: rating * (ratingCount > 0 ? ratingCount : 1),
      ratingCount: ratingCount,
      ambulanceType: AmbulanceType.bls,
    );
  }

  static Map<String, dynamic> driverToRow(
    RegisteredAmbulance profile, {
    String? ownerUid,
  }) {
    return {
      'ambulance_id': profile.id,
      if (ownerUid != null) 'owner_uid': ownerUid,
      'driver_name': profile.driverName,
      'vehicle_number': profile.vehicleNumber,
      'phone': profile.phone,
      'city': profile.city,
      'is_available': profile.available,
      'verified': profile.verified,
      'rating': profile.averageRating,
      'rating_count': profile.ratingCount,
      'metadata': {
        'service_name': profile.serviceName,
        'owner_name': profile.ownerName,
      },
    };
  }

  static AmbulanceBooking? bookingFromRow(Map<String, dynamic> row) {
    try {
      final statusStr = row['status'] as String? ?? 'pending';
      AmbulanceBookingStatus status;
      switch (statusStr.toLowerCase()) {
        case 'accepted':
        case 'in_progress':
        case 'dispatched':
          status = AmbulanceBookingStatus.accepted;
          break;
        case 'completed':
          status = AmbulanceBookingStatus.completed;
          break;
        case 'cancelled':
          status = AmbulanceBookingStatus.cancelled;
          break;
        case 'pending':
        default:
          status = AmbulanceBookingStatus.pending;
          break;
      }

      final createdAtRaw = row['created_at'] as String?;
      final dt = createdAtRaw != null ? DateTime.parse(createdAtRaw) : DateTime.now();

      final pickup = row['pickup_location'] as String? ?? row['pickup_address'] as String? ?? '';
      final phone = row['contact_phone'] as String? ?? row['patient_phone'] as String? ?? '';
      final driverId = row['accepted_driver_id'] as String? ?? row['assigned_driver_id'] as String?;

      return AmbulanceBooking(
        id: row['broadcast_id'] as String? ?? '',
        patientName: row['patient_name'] as String? ?? '',
        pickupLocation: pickup,
        contactPhone: phone,
        bookedByRole: AmbulanceBookedByRole.patient,
        bookedByName: row['patient_name'] as String? ?? '',
        bookedById: row['patient_id'] as String? ?? '',
        createdAt: dt,
        status: status,
        acceptedAmbulanceId: driverId,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> bookingToRow(
    AmbulanceBooking booking, {
    double? pickupLat,
    double? pickupLng,
    String? destinationAddress,
  }) {
    return {
      'broadcast_id': booking.id,
      'patient_id': booking.bookedById,
      'patient_name': booking.patientName,
      'pickup_location': booking.pickupLocation,
      'drop_location': destinationAddress ?? '',
      'contact_phone': booking.contactPhone,
      'status': booking.status.name,
      if (booking.acceptedAmbulanceId != null)
        'accepted_driver_id': booking.acceptedAmbulanceId,
    };
  }

  static AmbulanceRequest? requestFromRow(Map<String, dynamic> row) {
    try {
      final statusStr = row['status'] as String? ?? 'pending';
      AmbulanceRequestStatus status;
      switch (statusStr.toLowerCase()) {
        case 'accepted':
          status = AmbulanceRequestStatus.accepted;
          break;
        case 'cancelled':
        case 'rejected':
        case 'taken':
          status = AmbulanceRequestStatus.cancelled;
          break;
        case 'pending':
        default:
          status = AmbulanceRequestStatus.pending;
          break;
      }

      final createdAtRaw = row['created_at'] as String?;
      final dt = createdAtRaw != null ? DateTime.parse(createdAtRaw) : DateTime.now();

      final broadcast = row['ambulance_broadcasts'] as Map<String, dynamic>?;
      final pickup = row['pickup_location'] as String? ?? broadcast?['pickup_location'] as String? ?? broadcast?['pickup_address'] as String? ?? '';
      final drop = row['drop_location'] as String? ?? broadcast?['drop_location'] as String? ?? broadcast?['destination_address'] as String? ?? '';
      final patientId = row['patient_id'] as String? ?? broadcast?['patient_id'] as String? ?? '';

      return AmbulanceRequest(
        id: row['request_id'] as String? ?? '',
        driverId: row['driver_id'] as String? ?? '',
        patientId: patientId,
        pickupLocation: pickup,
        dropLocation: drop,
        status: status,
        createdAt: dt,
      );
    } catch (_) {
      return null;
    }
  }
}
