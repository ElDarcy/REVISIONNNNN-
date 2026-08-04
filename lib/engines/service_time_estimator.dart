class ServiceTimeEstimator {
  static const int baseProcessingMinutes = 120; // 2 hours base

  /// Minutes per laundry cycle (38 MINS PER CYCLE)
  static const int minutesPerCycle = 38;

  /// Default max kilograms per cycle (used when service data is unavailable)
  static const double defaultMaxKgPerCycle = 8.0;

  /// Get the number of cycles needed based on weight.
  static int getCycleCount(
    double weight, {
    double maxKgPerCycle = defaultMaxKgPerCycle,
  }) {
    if (weight <= 0) return 0;
    return (weight / maxKgPerCycle).ceil();
  }

  /// Estimate total processing time based on cycles (38 mins per cycle).
  static int estimateMinutesForCycles(int cycles) {
    if (cycles <= 0) return minutesPerCycle;
    return cycles * minutesPerCycle;
  }

  /// Estimate total processing time (38 minutes per cycle).
  static int estimateTotalMinutes(
    double weight,
    String serviceType,
    int estimatedMinutesPerKg,
  ) {
    final cycles = getCycleCount(weight);
    return estimateMinutesForCycles(cycles);
  }

  /// Get estimated completion time
  static DateTime estimateCompletionTime(
    DateTime startTime,
    double weight,
    String serviceType,
  ) {
    final minutes = estimateTotalMinutes(weight, serviceType, 120);
    return startTime.add(Duration(minutes: minutes));
  }

  /// Get estimated time by service type
  static int getEstimatedMinutes(String serviceType) {
    switch (serviceType) {
      case 'Wash & Dry':
        return 90;
      case 'Wash, Dry & Fold':
        return 120;
      case 'Dry Clean':
        return 180;
      case 'Iron Only':
        return 45;
      case 'Premium Care':
        return 150;
      default:
        return 120;
    }
  }

  /// Format estimated time
  static String formatEstimatedTime(int minutes) {
    if (minutes < 60) return '$minutes mins';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours hour(s)';
    return '${hours}h ${mins}m';
  }
}
