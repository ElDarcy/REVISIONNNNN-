import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

typedef ReverseGeocode = Future<List<Placemark>> Function(
  double latitude,
  double longitude,
);

/// Forward geocoding (address -> coordinates). The platform geocoder can
/// return multiple candidate matches for an ambiguous address.
typedef ForwardGeocode = Future<List<Location>> Function(String address);

class LocationService {
  LocationService({
    ReverseGeocode? reverseGeocode,
    ForwardGeocode? forwardGeocode,
  }) : _reverseGeocode = reverseGeocode ?? placemarkFromCoordinates,
       _forwardGeocode = forwardGeocode ?? locationFromAddress;

  static const _reverseGeocodeTimeout = Duration(seconds: 4);
  static const _reverseGeocodeAttempts = 2;
  static const _forwardGeocodeTimeout = Duration(seconds: 6);

  final ReverseGeocode _reverseGeocode;
  final ForwardGeocode _forwardGeocode;

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

    // BUG FIX: Add timeout so GPS failure never blocks checkout
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
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

  /// Resolves a coordinate into structured address components
  /// (street/barangay/city/province/postalCode) for form pre-fill. Best-effort.
  Future<Map<String, String>> getAddressComponents(
    double latitude,
    double longitude,
  ) async {
    const empty = {
      'street': '',
      'barangay': '',
      'city': '',
      'province': '',
      'postalCode': '',
    };
    if (!isValidCoordinate(latitude, longitude)) return empty;
    try {
      for (var attempt = 0; attempt < _reverseGeocodeAttempts; attempt++) {
        try {
          final placemarks = await _reverseGeocode(latitude, longitude)
              .timeout(_reverseGeocodeTimeout);
          if (placemarks.isEmpty) continue;
          final p = placemarks.first;
          return {
            'street': p.street?.trim() ?? '',
            'barangay': p.subLocality?.trim() ?? '',
            'city': p.locality?.trim() ?? '',
            'province': p.administrativeArea?.trim() ?? '',
            'postalCode': p.postalCode?.trim() ?? '',
          };
        } on TimeoutException {
          // Retry once before returning empty components.
        } catch (_) {
          // Transient platform geocoder failure; second attempt next loop.
        }
      }
      return empty;
    } catch (_) {
      return empty;
    }
  }

  /// Resolves a manually-entered address into candidate coordinates.
  ///
  /// Returns a de-duplicated list of `{latitude, longitude}` candidates from
  /// the platform geocoder. An empty list means the address could not be
  /// resolved. Multiple candidates must be shown to the customer for explicit
  /// selection — the first result is never silently chosen.
  Future<List<Map<String, double>>> getCoordinatesFromAddress(
    String address,
  ) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final locations = await _forwardGeocode(trimmed)
          .timeout(_forwardGeocodeTimeout);
      if (locations.isEmpty) return const [];

      final seen = <String>{};
      final candidates = <Map<String, double>>[];
      for (final loc in locations) {
        if (!isValidCoordinate(loc.latitude, loc.longitude)) continue;
        final key = '${loc.latitude.toStringAsFixed(5)},'
            '${loc.longitude.toStringAsFixed(5)}';
        if (seen.add(key)) {
          candidates.add({'latitude': loc.latitude, 'longitude': loc.longitude});
        }
      }
      return candidates;
    } catch (_) {
      // Platform geocoders are best-effort; the caller must surface the
      // unresolved state to the customer (retry or use GPS) rather than
      // fabricate coordinates.
      return const [];
    }
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
