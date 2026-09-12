import 'package:medibond/core/firebase/firestore_service.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../../features/pharmacy/models/pharmacy_models.dart';

bool locationsMatch(String location, String filter) {
  final left = location.trim().toLowerCase();
  final right = filter.trim().toLowerCase();
  if (right.isEmpty) return true;
  if (left.isEmpty) return false;
  return left.contains(right) || right.contains(left);
}

String normalizeCity(String value) => value.trim().toLowerCase();

/// Returns a non-empty city label from explicit city or a longer address string.
String? effectiveCityLabel({required String city, String? address}) {
  final trimmedCity = city.trim();
  if (trimmedCity.isNotEmpty) return trimmedCity;
  final trimmedAddress = address?.trim() ?? '';
  if (trimmedAddress.isNotEmpty) return trimmedAddress;
  return null;
}

bool cityFieldsMatch(String cityFilter, Iterable<String> fields) {
  final filter = cityFilter.trim();
  if (filter.isEmpty) return false;
  for (final field in fields) {
    if (locationsMatch(field, filter)) return true;
  }
  return false;
}

bool doctorMatchesCity(DoctorListing doctor, String cityFilter) {
  final filter = cityFilter.trim();
  if (filter.isEmpty) return true;
  return cityFieldsMatch(filter, [
    doctor.city,
    doctor.area,
    doctor.addressLine1,
    doctor.state,
    doctor.clinicName,
    doctor.locationLabel,
  ]);
}

bool medicalStoreMatchesCity(MedicalStoreProfile store, String cityFilter) {
  final filter = cityFilter.trim();
  if (filter.isEmpty) return false;
  return cityFieldsMatch(filter, [
    store.city,
    store.address,
    store.addressLine1,
    store.addressLine2,
    store.state,
  ]);
}

bool registeredLabMatchesCity(RegisteredLabProfile lab, String cityFilter) {
  final filter = cityFilter.trim();
  if (filter.isEmpty) return false;
  return cityFieldsMatch(filter, [
    lab.city,
    lab.area,
    lab.address,
    lab.addressLine1,
    lab.addressLine2,
    lab.state,
  ]);
}

bool ambulanceMatchesRequestCity({
  required String requestCity,
  required String ambulanceCity,
  Iterable<String> serviceAreas = const [],
  String? baseAddress,
}) {
  final filter = requestCity.trim();
  if (filter.isEmpty) return false;
  return cityFieldsMatch(filter, [
    ambulanceCity,
    baseAddress ?? '',
    ...serviceAreas,
  ]);
}

String? pharmacyCityFilter({required String city, required String address}) {
  return effectiveCityLabel(city: city, address: address);
}

String? readNestedAddressCity(Map<String, dynamic> data) {
  final address = data['address'];
  if (address is Map) {
    final city = address['city'];
    if (city is String && city.trim().isNotEmpty) return city.trim();
  }
  final topLevel = data['city'];
  if (topLevel is String && topLevel.trim().isNotEmpty) return topLevel.trim();
  return null;
}

String? readNestedAddressLine1(Map<String, dynamic> data) {
  final address = data['address'];
  if (address is Map) {
    final line = address['addressLine1'];
    if (line is String && line.trim().isNotEmpty) return line.trim();
  }
  final topLevel = data['addressLine1'];
  if (topLevel is String && topLevel.trim().isNotEmpty) return topLevel.trim();
  return null;
}
