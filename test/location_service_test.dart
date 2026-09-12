import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/services/location_service.dart';

void main() {
  group('LocationService & LocationResult tests', () {
    test('LocationResult stores address fields correctly', () {
      const result = LocationResult(
        latitude: 19.0760,
        longitude: 72.8777,
        addressLine1: 'Flat 101, Marine Drive',
        addressLine2: 'Nariman Point',
        city: 'Mumbai',
        state: 'Maharashtra',
        country: 'India',
        pincode: '400001',
        mapsUrl: 'https://www.google.com/maps/search/?api=1&query=19.076,72.8777',
      );

      expect(result.latitude, 19.0760);
      expect(result.longitude, 72.8777);
      expect(result.city, 'Mumbai');
      expect(result.state, 'Maharashtra');
      expect(result.country, 'India');
      expect(result.pincode, '400001');
      expect(result.addressLine1, 'Flat 101, Marine Drive');
      expect(result.mapsUrl, contains('query=19.076,72.8777'));
    });
  });
}
