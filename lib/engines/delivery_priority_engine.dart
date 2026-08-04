import '../models/delivery_model.dart';

class DeliveryPriorityEngine {
  /// Calculate priority score (lower = higher priority)
  static int calculatePriorityScore(DeliveryModel delivery) {
    int score = 0;

    // Distance factor (closer = higher priority)
    if (delivery.distanceKm <= 2) {
      score += 10; // Near
    } else if (delivery.distanceKm <= 5) {
      score += 20; // Medium
    } else if (delivery.distanceKm <= 10) {
      score += 30; // Far
    } else {
      score += 40; // Very Far
    }

    // Time factor (older = higher priority)
    final hoursSinceCreation = DateTime.now()
        .difference(delivery.createdAt)
        .inHours;
    if (hoursSinceCreation >= 24) {
      score -= 15; // Urgent
    } else if (hoursSinceCreation >= 12) {
      score -= 10; // High
    } else if (hoursSinceCreation >= 4) {
      score -= 5; // Medium
    }

    // Status factor
    if (delivery.status == 'Ready for Delivery') {
      score -= 5;
    } else if (delivery.status == 'Out for Delivery') {
      score -= 3;
    }

    return score;
  }

  /// Get priority label based on score
  static String getPriorityLabel(int score) {
    if (score <= 5) return 'High';
    if (score <= 15) return 'Medium';
    return 'Low';
  }

  /// Sort deliveries by priority
  static List<DeliveryModel> sortByPriority(List<DeliveryModel> deliveries) {
    final sorted = List<DeliveryModel>.from(deliveries);
    sorted.sort((a, b) {
      final scoreA = calculatePriorityScore(a);
      final scoreB = calculatePriorityScore(b);
      return scoreA.compareTo(scoreB);
    });
    return sorted;
  }
}
