import 'package:cloud_firestore/cloud_firestore.dart';

import 'ambulance_models.dart';

enum AmbulanceInviteStatus { pending, completed, expired }

class AmbulanceInvite {
  const AmbulanceInvite({
    required this.id,
    required this.token,
    required this.doctorId,
    required this.doctorName,
    required this.ambulanceId,
    required this.status,
    required this.serviceName,
    required this.ownerName,
    required this.driverName,
    required this.phone,
    required this.vehicleNumber,
    required this.ambulanceType,
    required this.city,
    required this.serviceAreas,
    required this.baseAddress,
    required this.licenseNumber,
    required this.insuranceNumber,
    required this.hasOxygen,
    required this.hasVentilator,
    required this.hasStretcher,
    required this.is24x7,
    this.ratePerKm,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String token;
  final String doctorId;
  final String doctorName;
  final String ambulanceId;
  final AmbulanceInviteStatus status;
  final String serviceName;
  final String ownerName;
  final String driverName;
  final String phone;
  final String vehicleNumber;
  final AmbulanceType ambulanceType;
  final String city;
  final List<String> serviceAreas;
  final String baseAddress;
  final String licenseNumber;
  final String insuranceNumber;
  final bool hasOxygen;
  final bool hasVentilator;
  final bool hasStretcher;
  final bool is24x7;
  final double? ratePerKm;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get isPending => status == AmbulanceInviteStatus.pending;

  RegisteredAmbulance toRegisteredAmbulance({
    required String username,
    required String pinHash,
  }) {
    return RegisteredAmbulance(
      id: ambulanceId,
      serviceName: serviceName,
      ownerName: ownerName,
      driverName: driverName,
      phone: phone,
      vehicleNumber: vehicleNumber,
      ambulanceType: ambulanceType,
      city: city,
      username: username,
      serviceAreas: serviceAreas,
      baseAddress: baseAddress,
      licenseNumber: licenseNumber,
      insuranceNumber: insuranceNumber,
      hasOxygen: hasOxygen,
      hasVentilator: hasVentilator,
      hasStretcher: hasStretcher,
      is24x7: is24x7,
      ratePerKm: ratePerKm,
      pin: pinHash,
      available: true,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  factory AmbulanceInvite.fromMap(String id, Map<String, dynamic> data) {
    AmbulanceType type = AmbulanceType.bls;
    final rawType = data['ambulanceType'] as String?;
    if (rawType != null) {
      type = AmbulanceType.values.where((t) => t.name == rawType).firstOrNull ??
          AmbulanceType.bls;
    }

    final rawStatus = data['status'] as String? ?? 'pending';
    final status = AmbulanceInviteStatus.values
            .where((s) => s.name == rawStatus)
            .firstOrNull ??
        AmbulanceInviteStatus.pending;

    return AmbulanceInvite(
      id: id,
      token: data['token'] as String? ?? '',
      doctorId: data['doctorId'] as String? ?? '',
      doctorName: data['doctorName'] as String? ?? '',
      ambulanceId: data['ambulanceId'] as String? ?? '',
      status: status,
      serviceName: data['serviceName'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? '',
      driverName: data['driverName'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      vehicleNumber: data['vehicleNumber'] as String? ?? '',
      ambulanceType: type,
      city: data['city'] as String? ?? '',
      serviceAreas:
          (data['serviceAreas'] as List<dynamic>?)?.cast<String>() ?? const [],
      baseAddress: data['baseAddress'] as String? ?? '',
      licenseNumber: data['licenseNumber'] as String? ?? '',
      insuranceNumber: data['insuranceNumber'] as String? ?? '',
      hasOxygen: data['hasOxygen'] as bool? ?? false,
      hasVentilator: data['hasVentilator'] as bool? ?? false,
      hasStretcher: data['hasStretcher'] as bool? ?? true,
      is24x7: data['is24x7'] as bool? ?? false,
      ratePerKm: (data['ratePerKm'] as num?)?.toDouble(),
      createdAt: _parseDate(data['createdAt']),
      expiresAt: _parseDate(data['expiresAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'token': token,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'ambulanceId': ambulanceId,
        'status': status.name,
        'serviceName': serviceName,
        'ownerName': ownerName,
        'driverName': driverName,
        'phone': phone,
        'vehicleNumber': vehicleNumber,
        'ambulanceType': ambulanceType.name,
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
      };

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
