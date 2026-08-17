import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

typedef ReverseGeocode = Future<List<Placemark>> Function(
  double latitude,
  double longitude,
);

class LocationService {
  LocationService({ReverseGeocode? reverseGeocode})
      : _reverseGeocode = reverseGeocode ?? placemarkFromCoordinates;

  static const _reverseGeocodeTimeout = Duration(seconds: 4);
  static const _reverseGeocodeAttempts = 2;

  final ReverseGeocode _reverseGeocode;

  static bool isValidCoordinate(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        !(latitude == 0 && longitude == 0);
  }

  Future<Position> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permissions are permanently denied. Please enable in settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<String> getAddressFromLatLng(
    double latitude,
    double longitude,
  ) async {
    if (!isValidCoordinate(latitude, longitude)) return '';

    try {
      for (var attempt = 0; attempt < _reverseGeocodeAttempts; attempt++) {
        try {
          final placemarks = await _reverseGeocode(latitude, longitude)
              .timeout(_reverseGeocodeTimeout);
          if (placemarks.isEmpty) continue;

          final address = formatPlacemark(placemarks.first);
          if (address.isNotEmpty) return address;
        } on TimeoutException {
          // Retry once before falling back to a coordinate-only location.
        } catch (_) {
          // Platform geocoding can fail transiently; the second attempt uses
          // the same valid customer coordinates and does not alter them.
        }
      }
      return '';
    } catch (_) {
      // Coordinates remain usable for navigation when the platform geocoder
      // is unavailable. An empty display address is intentional.
      return '';
    }
  }

  Future<Map<String, dynamic>> getLocationDetails() async {
    final position = await getCurrentLocation();
    return resolveLocationDetails(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  Future<Map<String, dynamic>> resolveLocationDetails({
    required double latitude,
    required double longitude,
  }) async {
    if (!isValidCoordinate(latitude, longitude)) {
      throw Exception('The device returned an invalid location.');
    }

    final address = await getAddressFromLatLng(
      latitude,
      longitude,
    );

    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
    };
  }

  /// Formats whatever the platform geocoder could resolve. Fields are
  /// optional on Android/iOS, so a partial placemark is still useful.
  static String formatPlacemark(Placemark place) {
    final parts = <String>[];
    final seen = <String>{};
    for (final value in <String?>[
      place.street,
      place.subLocality,
      place.locality,
      place.subAdministrativeArea,
      place.administrativeArea,
      place.country,
    ]) {
      final cleaned = value?.trim() ?? '';
      final key = cleaned.toLowerCase();
      if (cleaned.isNotEmpty && seen.add(key)) {
        parts.add(cleaned);
      }
    }
    return parts.join(', ');
  }

  static double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng) /
        1000; // Convert to km
  }
}
