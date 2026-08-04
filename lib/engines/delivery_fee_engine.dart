class DeliveryFeeEngine {
  static const double baseFee = 20.0;
  static const double perKmFee = 10.0;

  /// Round distance to 1 decimal place
  static double roundDistance(double distanceKm) {
    if (distanceKm <= 0) return 0;
    return (distanceKm * 10).round() / 10.0;
  }

  /// Round fee to whole peso
  static double roundFeeToWhole(double fee) {
    return fee.roundToDouble();
  }

  /// Calculate delivery fee based on distance
  /// Distance is rounded to 1 decimal before computation
  /// Final fee is rounded to whole peso
  static double calculateFee(double distanceKm) {
    if (distanceKm <= 0) return 0;
    final roundedDistance = roundDistance(distanceKm);
    final fee = baseFee + (roundedDistance * perKmFee);
    return roundFeeToWhole(fee);
  }

  /// Calculate fee with potential discounts
  static double calculateDiscountedFee(
    double distanceKm, {
    double discountPercent = 0,
  }) {
    final fee = calculateFee(distanceKm);
    return roundFeeToWhole(fee * (1 - discountPercent / 100));
  }

  /// Get fee breakdown (all values rounded appropriately)
  static Map<String, dynamic> getFeeBreakdown(double distanceKm) {
    final roundedDistance = roundDistance(distanceKm);
    final distanceFee = roundFeeToWhole(roundedDistance * perKmFee);
    final total = roundFeeToWhole(baseFee + distanceFee);

    return {
      'baseFee': baseFee,
      'distanceFee': distanceFee,
      'distanceKm': roundedDistance,
      'totalFee': total,
    };
  }

  /// Check if free delivery applies
  static bool isFreeDelivery(double distanceKm, double minOrderAmount) {
    final roundedDistance = roundDistance(distanceKm);
    return roundedDistance <= 1 && minOrderAmount >= 200;
  }
}
