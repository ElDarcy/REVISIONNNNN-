import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:laundry_app/services/location_service.dart';

void main() {
  test('valid coordinates resolve to a readable address', () async {
    final service = LocationService(
      reverseGeocode: (_, _) async => const [
        Placemark(
          street: 'Purok 1',
          subLocality: 'Brgy. Santo Cristo',
          locality: 'Malolos',
          administrativeArea: 'Bulacan',
          country: 'Philippines',
        ),
      ],
    );

    expect(
      await service.getAddressFromLatLng(14.8432, 120.8111),
      'Purok 1, Brgy. Santo Cristo, Malolos, Bulacan, Philippines',
    );
  });

  test('partial reverse-geocoding response produces a best-effort address', () {
    expect(
      LocationService.formatPlacemark(
        const Placemark(
          locality: 'Meycauayan',
          administrativeArea: 'Bulacan',
          country: 'Philippines',
        ),
      ),
      'Meycauayan, Bulacan, Philippines',
    );
  });

  test('reverse-geocoding failure retains valid coordinates', () async {
    var attempts = 0;
    final service = LocationService(
      reverseGeocode: (_, _) async {
        attempts++;
        throw Exception('temporary platform geocoder failure');
      },
    );

    final result = await service.resolveLocationDetails(
      latitude: 14.8432,
      longitude: 120.8111,
    );

    expect(result['latitude'], 14.8432);
    expect(result['longitude'], 120.8111);
    expect(result['address'], isEmpty);
    expect(attempts, 2);
  });
}
