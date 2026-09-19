import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../constants/countries.dart';
import '../constants/world_locations.dart';
import '../notifications/app_toast.dart';

/// Structured result holding auto-detected location and address fields.
class LocationResult {
  const LocationResult({
    required this.latitude,
    required this.longitude,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.country,
    this.pincode,
    this.fullAddress,
    this.mapsUrl,
  });

  final double latitude;
  final double longitude;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? country;
  final String? pincode;
  final String? fullAddress;
  final String? mapsUrl;

  @override
  String toString() =>
      'LocationResult(lat: $latitude, lon: $longitude, city: $city, state: $state, country: $country, pincode: $pincode)';
}

/// Robust, cross-platform Location Service for Web, Android, iOS, and Desktop.
abstract final class LocationService {
  LocationService._();

  /// Requests permissions and fetches the device or browser's current GPS location and reverse-geocodes it into structured address fields.
  static Future<LocationResult?> getCurrentLocation({
    BuildContext? context,
    bool showToast = true,
  }) async {
    try {
      // 1. Check if location services are enabled (skipped on web because browser handles it via permissions)
      if (!kIsWeb) {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (context != null && context.mounted && showToast) {
            AppToast.error(context, 'Location services are disabled. Please turn on GPS.');
          }
          return null;
        }
      }

      // 2. Permission check & request
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (context != null && context.mounted && showToast) {
            AppToast.error(context, 'Location permission denied.');
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (context != null && context.mounted && showToast) {
          AppToast.error(context, 'Location permissions are permanently denied. Please enable in settings.');
        }
        return null;
      }

      // 3. Acquire current position
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      String? line1;
      String? line2;
      String? city;
      String? state;
      String? country;
      String? pincode;
      String? fullAddress;

      // 4. Try native geocoding (iOS & Android)
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final pm = placemarks.first;
          line1 = pm.street;
          line2 = pm.subLocality;
          country = pm.country;
          state = pm.administrativeArea;
          city = pm.locality ?? pm.subAdministrativeArea;
          pincode = pm.postalCode;
        }
      } catch (_) {
        // Native geocoding may fail on Web or Windows — fallback to OpenStreetMap
      }

      // 5. Fallback: Free OpenStreetMap Nominatim reverse geocoder (100% Web & Desktop compatible)
      if (city == null || state == null || country == null || pincode == null) {
        try {
          final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
            'lat': '${pos.latitude}',
            'lon': '${pos.longitude}',
            'format': 'json',
            'addressdetails': '1',
          });
          final response = await http.get(
            uri,
            headers: const {'User-Agent': 'DoctorNect/1.0 (healthcare-ecosystem-app)'},
          ).timeout(const Duration(seconds: 6));

          if (response.statusCode == 200) {
            final payload = jsonDecode(response.body) as Map<String, dynamic>;
            final address = payload['address'] as Map<String, dynamic>?;
            fullAddress ??= payload['display_name'] as String?;

            if (address != null) {
              city ??= (address['city'] ??
                      address['town'] ??
                      address['village'] ??
                      address['suburb'] ??
                      address['county'])
                  ?.toString();
              state ??= (address['state'] ?? address['province'] ?? address['region'])?.toString();
              country ??= address['country']?.toString();
              pincode ??= address['postcode']?.toString();

              final road = address['road']?.toString();
              final houseNumber = address['house_number']?.toString();
              final neighbourhood = (address['suburb'] ??
                      address['neighbourhood'] ??
                      address['residential'] ??
                      address['quarter'])
                  ?.toString();

              if (line1 == null || line1.isEmpty) {
                line1 = [
                  if (houseNumber != null && houseNumber.isNotEmpty) houseNumber,
                  if (road != null && road.isNotEmpty) road,
                ].join(' ');
                if (line1.isEmpty) line1 = neighbourhood;
              }
              line2 ??= neighbourhood != line1 ? neighbourhood : null;
            }
          }
        } catch (_) {}
      }

      // 6. Normalize Country against Countries.all
      if (country != null) {
        final matchedCountry = _matchCountry(country);
        if (matchedCountry != null) {
          country = matchedCountry;
        }
      }

      // 7. Normalize State against WorldLocations
      if (country != null && state != null) {
        final matchedState = _matchState(country, state);
        if (matchedState != null) {
          state = matchedState;
        }
      }

      // 8. Normalize City against WorldLocations
      if (country != null && state != null && city != null) {
        final matchedCity = _matchCity(country, state, city);
        if (matchedCity != null) {
          city = matchedCity;
        }
      }

      final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';

      final result = LocationResult(
        latitude: pos.latitude,
        longitude: pos.longitude,
        addressLine1: line1?.trim().isNotEmpty == true ? line1!.trim() : null,
        addressLine2: line2?.trim().isNotEmpty == true ? line2!.trim() : null,
        city: city?.trim().isNotEmpty == true ? city!.trim() : null,
        state: state?.trim().isNotEmpty == true ? state!.trim() : null,
        country: country?.trim().isNotEmpty == true ? country!.trim() : null,
        pincode: pincode?.trim().isNotEmpty == true ? pincode!.trim() : null,
        fullAddress: fullAddress,
        mapsUrl: mapsUrl,
      );

      return result;
    } catch (e) {
      if (context != null && context.mounted && showToast) {
        AppToast.error(context, 'Failed to detect location. Please enter manually.');
      }
      return null;
    }
  }

  static String? _matchCountry(String raw) {
    final lower = raw.trim().toLowerCase();
    for (final c in Countries.all) {
      if (c.toLowerCase() == lower || lower.contains(c.toLowerCase()) || c.toLowerCase().contains(lower)) {
        return c;
      }
    }
    return raw.trim();
  }

  static String? _matchState(String country, String raw) {
    final lower = raw.trim().toLowerCase();
    final states = WorldLocations.statesFor(country);
    for (final s in states) {
      if (s.toLowerCase() == lower || lower.contains(s.toLowerCase()) || s.toLowerCase().contains(lower)) {
        return s;
      }
    }
    return raw.trim();
  }

  static String? _matchCity(String country, String state, String raw) {
    final lower = raw.trim().toLowerCase();
    final cities = WorldLocations.citiesFor(country, state);
    for (final c in cities) {
      if (c.toLowerCase() == lower || lower.contains(c.toLowerCase()) || c.toLowerCase().contains(lower)) {
        return c;
      }
    }
    return raw.trim();
  }
}
