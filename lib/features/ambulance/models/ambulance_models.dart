enum AmbulanceBookingStatus { pending, accepted, completed, cancelled }

enum AmbulanceRequestStatus { pending, accepted, cancelled }

/// Firestore-backed ambulance driver listing for area-based matching.
class AmbulanceDriverProfile {
  const AmbulanceDriverProfile({
    required this.id,
    required this.driverName,
    required this.ambulanceType,
    required this.vehicleNumber,
    required this.serviceArea,
    this.phone,
    this.serviceName,
    this.isAvailable = true,
  });

  final String id;
  final String driverName;
  final String ambulanceType;
  final String vehicleNumber;
  final String serviceArea;
  final String? phone;
  final String? serviceName;
  final bool isAvailable;

  String get displayServiceName =>
      serviceName?.trim().isNotEmpty == true ? serviceName!.trim() : ambulanceType;
}

class AmbulanceRequest {
  const AmbulanceRequest({
    required this.id,
    required this.driverId,
    required this.patientId,
    required this.pickupLocation,
    required this.dropLocation,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String driverId;
  final String patientId;
  final String pickupLocation;
  final String dropLocation;
  final AmbulanceRequestStatus status;
  final DateTime createdAt;
}

enum AmbulanceBookedByRole { doctor, patient }

enum AmbulanceType { bls, als, icu, patientTransport }

class RegisteredAmbulance {
  const RegisteredAmbulance({
    required this.id,
    required this.serviceName,
    required this.driverName,
    required this.phone,
    required this.vehicleNumber,
    required this.city,
    this.username = '',
    this.ownerName = '',
    this.ambulanceType = AmbulanceType.bls,
    this.serviceAreas = const [],
    this.baseAddress = '',
    this.licenseNumber = '',
    this.insuranceNumber = '',
    this.hasOxygen = false,
    this.hasVentilator = false,
    this.hasStretcher = true,
    this.is24x7 = false,
    this.ratePerKm,
    this.pin = '',
    this.totalRating = 0.0,
    this.ratingCount = 0,
    this.available = true,
    this.createdAt,
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.country = '',
    this.state = '',
    this.pincode = '',
  });

  final String id;
  final String serviceName;
  final String ownerName;
  final String driverName;
  final String phone;
  final String vehicleNumber;
  final AmbulanceType ambulanceType;
  final String city;
  final String username;
  final List<String> serviceAreas;
  final String baseAddress;
  final String licenseNumber;
  final String insuranceNumber;
  final bool hasOxygen;
  final bool hasVentilator;
  final bool hasStretcher;
  final bool is24x7;
  final double? ratePerKm;
  final String pin;
  final double totalRating;
  final int ratingCount;
  final bool available;
  final DateTime? createdAt;
  final String addressLine1;
  final String addressLine2;
  final String country;
  final String state;
  final String pincode;

  double get averageRating => ratingCount > 0 ? totalRating / ratingCount : 0.0;

  RegisteredAmbulance copyWith({
    String? serviceName,
    String? ownerName,
    String? driverName,
    String? phone,
    String? vehicleNumber,
    AmbulanceType? ambulanceType,
    String? city,
    String? username,
    List<String>? serviceAreas,
    String? baseAddress,
    String? licenseNumber,
    String? insuranceNumber,
    bool? hasOxygen,
    bool? hasVentilator,
    bool? hasStretcher,
    bool? is24x7,
    double? ratePerKm,
    String? pin,
    double? totalRating,
    int? ratingCount,
    bool? available,
    DateTime? createdAt,
    String? addressLine1,
    String? addressLine2,
    String? country,
    String? state,
    String? pincode,
  }) {
    return RegisteredAmbulance(
      id: id,
      serviceName: serviceName ?? this.serviceName,
      ownerName: ownerName ?? this.ownerName,
      driverName: driverName ?? this.driverName,
      phone: phone ?? this.phone,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      ambulanceType: ambulanceType ?? this.ambulanceType,
      city: city ?? this.city,
      username: username ?? this.username,
      serviceAreas: serviceAreas ?? this.serviceAreas,
      baseAddress: baseAddress ?? this.baseAddress,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      insuranceNumber: insuranceNumber ?? this.insuranceNumber,
      hasOxygen: hasOxygen ?? this.hasOxygen,
      hasVentilator: hasVentilator ?? this.hasVentilator,
      hasStretcher: hasStretcher ?? this.hasStretcher,
      is24x7: is24x7 ?? this.is24x7,
      ratePerKm: ratePerKm ?? this.ratePerKm,
      pin: pin ?? this.pin,
      totalRating: totalRating ?? this.totalRating,
      ratingCount: ratingCount ?? this.ratingCount,
      available: available ?? this.available,
      createdAt: createdAt ?? this.createdAt,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      country: country ?? this.country,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
    );
  }

  String get ambulanceTypeLabel => switch (ambulanceType) {
        AmbulanceType.bls => 'BLS (Basic)',
        AmbulanceType.als => 'ALS (Advanced)',
        AmbulanceType.icu => 'ICU',
        AmbulanceType.patientTransport => 'Patient Transport',
      };

  Map<String, dynamic> toMap({bool includePrivateFields = true}) => {
        'serviceName': serviceName,
        'ownerName': ownerName,
        'driverName': driverName,
        'phone': phone,
        'vehicleNumber': vehicleNumber,
        'ambulanceType': ambulanceType.name,
        'username': username,
        'city': city,
        'serviceAreas': serviceAreas,
        'baseAddress': baseAddress,
        'licenseNumber': licenseNumber,
        'insuranceNumber': insuranceNumber,
        'hasOxygen': hasOxygen,
        'hasVentilator': hasVentilator,
        'hasStretcher': hasStretcher,
        'is24x7': is24x7,
        if (ratePerKm != null) 'ratePerKm': ratePerKm,
        if (includePrivateFields && pin.isNotEmpty) 'pin': pin,
        'totalRating': totalRating,
        'ratingCount': ratingCount,
        'isAvailable': available,
        'createdAt': createdAt?.toIso8601String(),
        'address': {
          'addressLine1': addressLine1,
          'addressLine2': addressLine2,
          'country': country,
          'state': state,
          'city': city,
          'pinCode': pincode,
        },
      };

  factory RegisteredAmbulance.fromMap(String id, Map<String, dynamic> data) {
    AmbulanceType type = AmbulanceType.bls;
    final raw = data['ambulanceType'] as String?;
    if (raw != null) {
      type = AmbulanceType.values.where((t) => t.name == raw).firstOrNull ?? AmbulanceType.bls;
    }

    final addressData = data['address'];
    String aCountry = '';
    String aState = '';
    String aCity = data['city'] as String? ?? '';
    String aLine1 = '';
    String aLine2 = '';
    String aPinCode = '';

    if (addressData is Map) {
      aCountry = addressData['country'] as String? ?? '';
      aState = addressData['state'] as String? ?? '';
      aCity = addressData['city'] as String? ?? aCity;
      aLine1 = addressData['addressLine1'] as String? ?? '';
      aLine2 = addressData['addressLine2'] as String? ?? '';
      aPinCode = addressData['pinCode'] as String? ?? '';
    }

    return RegisteredAmbulance(
      id: id,
      serviceName: data['serviceName'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? '',
      driverName: data['driverName'] as String? ?? 'Driver',
      phone: data['phone'] as String? ?? '',
      vehicleNumber: data['vehicleNumber'] as String? ?? '',
      ambulanceType: type,
      username: data['username'] as String? ?? '',
      city: aCity,
      serviceAreas: (data['serviceAreas'] as List<dynamic>?)?.cast<String>() ?? const [],
      baseAddress: data['baseAddress'] as String? ?? '',
      licenseNumber: data['licenseNumber'] as String? ?? '',
      insuranceNumber: data['insuranceNumber'] as String? ?? '',
      hasOxygen: data['hasOxygen'] as bool? ?? false,
      hasVentilator: data['hasVentilator'] as bool? ?? false,
      hasStretcher: data['hasStretcher'] as bool? ?? true,
      is24x7: data['is24x7'] as bool? ?? false,
      ratePerKm: (data['ratePerKm'] as num?)?.toDouble(),
      pin: data['pin'] as String? ?? '',
      totalRating: (data['totalRating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: data['ratingCount'] as int? ?? 0,
      available: data['isAvailable'] as bool? ?? true,
      addressLine1: aLine1,
      addressLine2: aLine2,
      country: aCountry,
      state: aState,
      pincode: aPinCode,
    );
  }
}

class AmbulanceBooking {
  AmbulanceBooking({
    required this.id,
    required this.patientName,
    required this.pickupLocation,
    required this.contactPhone,
    required this.bookedByRole,
    required this.bookedByName,
    required this.bookedById,
    required this.createdAt,
    this.notes,
    this.status = AmbulanceBookingStatus.pending,
    this.acceptedAmbulanceId,
    this.acceptedAmbulanceName,
    this.acceptedDriverName,
    this.acceptedDriverPhone,
    this.acceptedVehicleNumber,
    this.acceptedAmbulanceType,
    this.acceptedAt,
    this.rating,
    this.review,
    this.firestoreRequestId,
    this.rawStatus,
  });

  final String id;
  final String? firestoreRequestId;
  final String patientName;
  final String pickupLocation;
  final String contactPhone;
  final String? notes;
  final AmbulanceBookedByRole bookedByRole;
  final String bookedByName;
  final String bookedById;
  final DateTime createdAt;
  AmbulanceBookingStatus status;
  String? acceptedAmbulanceId;
  String? acceptedAmbulanceName;
  String? acceptedDriverName;
  String? acceptedDriverPhone;
  String? acceptedVehicleNumber;
  String? acceptedAmbulanceType;
  DateTime? acceptedAt;
  int? rating;
  String? review;
  String? rawStatus;

  bool get isPending => status == AmbulanceBookingStatus.pending;
  bool get isAccepted => status == AmbulanceBookingStatus.accepted;
  bool get isCompleted => status == AmbulanceBookingStatus.completed;
  bool get isCancelled => status == AmbulanceBookingStatus.cancelled;
  bool get isRated => rating != null && rating! > 0;
  bool get isRatingSkipped => rating == -1;

  AmbulanceBooking copyWithAccepted({
    required RegisteredAmbulance ambulance,
    required DateTime acceptedAt,
  }) {
    return AmbulanceBooking(
      id: id,
      patientName: patientName,
      pickupLocation: pickupLocation,
      contactPhone: contactPhone,
      notes: notes,
      bookedByRole: bookedByRole,
      bookedByName: bookedByName,
      bookedById: bookedById,
      createdAt: createdAt,
      status: AmbulanceBookingStatus.accepted,
      acceptedAmbulanceId: ambulance.id,
      acceptedAmbulanceName: ambulance.serviceName,
      acceptedDriverName: ambulance.driverName,
      acceptedDriverPhone: ambulance.phone,
      acceptedVehicleNumber: ambulance.vehicleNumber,
      acceptedAmbulanceType: ambulance.ambulanceTypeLabel,
      acceptedAt: acceptedAt,
      rawStatus: rawStatus,
    );
  }

  AmbulanceBooking copyWithCancelled({String? rawStatus}) {
    return AmbulanceBooking(
      id: id,
      patientName: patientName,
      pickupLocation: pickupLocation,
      contactPhone: contactPhone,
      notes: notes,
      bookedByRole: bookedByRole,
      bookedByName: bookedByName,
      bookedById: bookedById,
      createdAt: createdAt,
      status: AmbulanceBookingStatus.cancelled,
      rawStatus: rawStatus ?? this.rawStatus,
    );
  }

  AmbulanceBooking copyWithCompleted() {
    return AmbulanceBooking(
      id: id,
      patientName: patientName,
      pickupLocation: pickupLocation,
      contactPhone: contactPhone,
      notes: notes,
      bookedByRole: bookedByRole,
      bookedByName: bookedByName,
      bookedById: bookedById,
      createdAt: createdAt,
      status: AmbulanceBookingStatus.completed,
      acceptedAmbulanceId: acceptedAmbulanceId,
      acceptedAmbulanceName: acceptedAmbulanceName,
      acceptedDriverName: acceptedDriverName,
      acceptedDriverPhone: acceptedDriverPhone,
      acceptedVehicleNumber: acceptedVehicleNumber,
      acceptedAmbulanceType: acceptedAmbulanceType,
      acceptedAt: acceptedAt,
      rawStatus: rawStatus,
    );
  }

  AmbulanceBooking copyWithRating({required int stars, String? reviewText}) {
    return AmbulanceBooking(
      id: id,
      patientName: patientName,
      pickupLocation: pickupLocation,
      contactPhone: contactPhone,
      notes: notes,
      bookedByRole: bookedByRole,
      bookedByName: bookedByName,
      bookedById: bookedById,
      createdAt: createdAt,
      status: status,
      acceptedAmbulanceId: acceptedAmbulanceId,
      acceptedAmbulanceName: acceptedAmbulanceName,
      acceptedDriverName: acceptedDriverName,
      acceptedDriverPhone: acceptedDriverPhone,
      acceptedVehicleNumber: acceptedVehicleNumber,
      acceptedAmbulanceType: acceptedAmbulanceType,
      acceptedAt: acceptedAt,
      rating: stars,
      review: reviewText,
      rawStatus: rawStatus,
    );
  }
}

class AmbulanceDriverAlert {
  const AmbulanceDriverAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.bookingId,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? bookingId;
  final bool isRead;

  AmbulanceDriverAlert copyWith({bool? isRead}) => AmbulanceDriverAlert(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        bookingId: bookingId,
        isRead: isRead ?? this.isRead,
      );
}
