import '../models/order_model.dart';
import '../models/delivery_queue_entry_model.dart';

/// A rule-based staff assignment recommendation engine.
///
/// Recommends the most suitable staff member based on current workload
/// distribution while allowing the admin to manually override the
/// recommendation.
///
/// Recommendation priority:
/// 1. Lowest active workload count.
/// 2. If workload is equal, longest idle time (least recently active).
/// 3. If still tied, lowest staff ID.
class StaffAssignmentEngine {
  static const Set<String> _finishedStatuses = {
    'Completed',
    'Delivered',
    'Cancelled',
    'Rejected',
  };

  static const Set<String> _activeDeliveryStatuses = {
    'Pending Delivery',
    'Out for Delivery',
  };

  /// Whether an order should count towards a staff member's active workload.
  static bool isActiveOrder(OrderModel order) {
    return !_finishedStatuses.contains(order.status.value);
  }

  /// Build a map of `staffId -> active order workload count` from the given
  /// orders. Only orders assigned via `assignedTo`/`staffId` are counted.
  static Map<String, int> countActiveOrdersByStaff(List<OrderModel> orders) {
    final counts = <String, int>{};
    for (final order in orders) {
      final staffId = order.assignedTo ?? order.staffId;
      if (staffId == null || staffId.isEmpty) continue;
      if (!isActiveOrder(order)) continue;
      counts[staffId] = (counts[staffId] ?? 0) + 1;
    }
    return counts;
  }

  /// Build a map of `staffId -> oldest active order assignment time` for
  /// idle-time tie-breaking. Uses the earliest (oldest) activity timestamp
  /// as a proxy for "has been busy since"; a staff member with no active
  /// orders has the longest idle time.
  static Map<String, DateTime> lastActiveByStaff(List<OrderModel> orders) {
    final lastActive = <String, DateTime>{};
    for (final order in orders) {
      final staffId = order.assignedTo ?? order.staffId;
      if (staffId == null || staffId.isEmpty) continue;

      // Use the most recent activity timestamp of each order.
      final activity =
          order.updatedAt ??
          order.completedAt ??
          order.approvedAt ??
          order.createdAt;

      final current = lastActive[staffId];
      if (current == null || activity.isAfter(current)) {
        lastActive[staffId] = activity;
      }
    }
    return lastActive;
  }

  /// Build a map of `deliveryStaffId -> active delivery workload count` from
  /// the given delivery queue entries. Counts entries that are pending or
  /// currently out for delivery, regardless of assignment (they still occupy
  /// the delivery pipeline).
  static Map<String, int> countActiveDeliveriesByStaff(
    List<DeliveryQueueEntry> queue,
  ) {
    final counts = <String, int>{};
    for (final entry in queue) {
      if (!_activeDeliveryStatuses.contains(entry.status)) continue;
      final staffId = entry.assignedTo;
      if (staffId == null || staffId.isEmpty) continue;
      counts[staffId] = (counts[staffId] ?? 0) + 1;
    }
    return counts;
  }

  /// Recommend the best staff member from [staffIds] using the workload
  /// balancing rules.
  ///
  /// - [activeWorkloads]: `staffId -> current active task count`.
  /// - [lastActive]: `staffId -> most recent activity time` (nullable).
  ///
  /// Returns the recommended staff id, or `null` when no staff is available.
  static String? recommendStaffId({
    required List<String> staffIds,
    Map<String, int> activeWorkloads = const {},
    Map<String, DateTime>? lastActive,
  }) {
    if (staffIds.isEmpty) return null;

    final workset = staffIds.toList()..sort();

    workset.sort((a, b) {
      // 1. Lowest active workload first.
      final workloadA = activeWorkloads[a] ?? 0;
      final workloadB = activeWorkloads[b] ?? 0;
      if (workloadA != workloadB) return workloadA.compareTo(workloadB);

      // 2. Longest idle time first (least recently active).
      final lastA = lastActive?[a];
      final lastB = lastActive?[b];
      // A staff with no activity is the most idle.
      if (lastA == null && lastB != null) return -1;
      if (lastA != null && lastB == null) return 1;
      if (lastA != null && lastB != null && !lastA.isAtSameMomentAs(lastB)) {
        // Older timestamp = idle longer = preferred, so ascending order.
        return lastA.compareTo(lastB);
      }

      // 3. Lowest staff ID.
      return a.compareTo(b);
    });

    return workset.first;
  }
}
