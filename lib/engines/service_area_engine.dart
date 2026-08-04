import 'distance_engine.dart';

class ServiceAreaEngine {
  static const double maxDeliveryRadius = 15.0; // km

  /// Check if customer location is within service area
  static bool isInServiceArea(double customerLat, double customerLng) {
    final distance = DistanceEngine.distanceFromShop(customerLat, customerLng);
    return distance <= maxDeliveryRadius;
  }

  /// Get detailed service area info
  static Map<String, dynamic> getServiceAreaInfo(
    double customerLat,
    double customerLng,
  ) {
    final distance = DistanceEngine.distanceFromShop(customerLat, customerLng);
    final inArea = distance <= maxDeliveryRadius;

    return {
      'inServiceArea': inArea,
      'distanceKm': distance,
      'maxRadius': maxDeliveryRadius,
      'remainingKm': inArea ? maxDeliveryRadius - distance : 0,
      'distanceCategory': DistanceEngine.getDistanceCategory(distance),
    };
  }

  /// Get estimated delivery time based on distance
  static String getEstimatedDeliveryTime(double distanceKm) {
    if (distanceKm <= 2) return '30-45 mins';
    if (distanceKm <= 5) return '45-60 mins';
    if (distanceKm <= 10) return '1-2 hours';
    return '2-3 hours';
  }
}
