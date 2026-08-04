import 'dart:math';

class DistanceEngine {
  static const double earthRadiusKm = 6371.0;
  static const double shopLat = 14.653173;
  static const double shopLng = 120.967443;

  /// Calculate distance between two points using Haversine formula
  static double calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Calculate distance from shop to customer
  static double distanceFromShop(double customerLat, double customerLng) {
    return calculateDistance(shopLat, shopLng, customerLat, customerLng);
  }

  /// Check if distance is within delivery range
  static bool isWithinRange(double distanceKm, double maxRangeKm) {
    return distanceKm <= maxRangeKm;
  }

  static double _toRadians(double degree) {
    return degree * pi / 180;
  }

  /// Get distance category
  static String getDistanceCategory(double distanceKm) {
    if (distanceKm <= 2) return 'Near';
    if (distanceKm <= 5) return 'Medium';
    if (distanceKm <= 10) return 'Far';
    return 'Very Far';
  }
}
