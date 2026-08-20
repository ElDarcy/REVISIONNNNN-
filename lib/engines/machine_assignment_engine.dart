import '../models/machine_model.dart';
import '../models/order_load_model.dart';
import '../core/constants/app_constants.dart';

/// Engine that selects the best available machine using a
/// least-used (balanced workload) algorithm:
///
/// 1. Filter machines by type ('wash' or 'dry') that are available.
/// 2. Sort by usageCount ascending (least-used first).
/// 3. Tie-break by lastUsed ascending (oldest first), so machines that
///    have been idle the longest are preferred when usage counts tie.
class MachineAssignmentEngine {
  /// Select the best available machine of a given type using the
  /// least-used algorithm. Returns null when no machine is available.
  static MachineModel? findBestAvailableMachine(
    List<MachineModel> machines,
    String type,
  ) {
    final ranked = rankAvailableMachines(machines, type);
    return ranked.isNotEmpty ? ranked.first : null;
  }

  /// Returns available machines of the given type sorted by the
  /// least-used algorithm (usageCount ASC, then lastUsed ASC).
  static List<MachineModel> rankAvailableMachines(
    List<MachineModel> machines,
    String type,
  ) {
    final available = machines
        .where(
          (m) => m.type == type && m.status == AppConstants.machineAvailable,
        )
        .toList();

    available.sort((a, b) {
      // Primary: least usage count first
      final usageCompare = a.usageCount.compareTo(b.usageCount);
      if (usageCompare != 0) return usageCompare;

      // Secondary: oldest lastUsed first (machines idle the longest)
      final aLast = a.lastUsed ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bLast = b.lastUsed ?? DateTime.fromMillisecondsSinceEpoch(0);
      final lastCompare = aLast.compareTo(bLast);
      if (lastCompare != 0) return lastCompare;

      // Tertiary: lowest machine number
      return a.machineNumber.compareTo(b.machineNumber);
    });

    return available;
  }

  /// Whether at least one machine of the given type is available.
  static bool hasAvailableMachine(List<MachineModel> machines, String type) {
    return machines.any(
      (m) => m.type == type && m.status == AppConstants.machineAvailable,
    );
  }

  /// Whether at least one machine of the given type is currently in use.
  static bool hasMachineInUse(List<MachineModel> machines, String type) {
    return machines.any((m) {
      if (m.type != type) return false;
      return m.status == AppConstants.machineWashing ||
          m.status == AppConstants.machineDrying;
    });
  }

  /// Count of available machines of the given type.
  static int countAvailable(List<MachineModel> machines, String type) {
    return machines
        .where(
          (m) => m.type == type && m.status == AppConstants.machineAvailable,
        )
        .length;
  }

  /// Count of in-use machines of the given type.
  static int countInUse(List<MachineModel> machines, String type) {
    return machines.where((m) {
      if (m.type != type) return false;
      return m.status == AppConstants.machineWashing ||
          m.status == AppConstants.machineDrying;
    }).length;
  }

  /// The most used machine of a given type (largest usageCount).
  static MachineModel? findMostUsed(List<MachineModel> machines, String type) {
    final list = machines.where((m) => m.type == type).toList();
    if (list.isEmpty) return null;
    list.sort((a, b) => b.usageCount.compareTo(a.usageCount));
    return list.first;
  }

  /// The least used machine of a given type (smallest usageCount).
  static MachineModel? findLeastUsed(List<MachineModel> machines, String type) {
    final list = machines.where((m) => m.type == type).toList();
    if (list.isEmpty) return null;
    list.sort((a, b) => a.usageCount.compareTo(b.usageCount));
    return list.first;
  }

  /// Total wash cycles across all washing machines.
  static int totalWashCycles(List<MachineModel> machines) {
    return machines
        .where((m) => m.type == AppConstants.machineWasher)
        .fold<int>(0, (sum, m) => sum + m.usageCount);
  }

  /// Total dry cycles across all dryers.
  static int totalDryCycles(List<MachineModel> machines) {
    return machines
        .where((m) => m.type == AppConstants.machineDryer)
        .fold<int>(0, (sum, m) => sum + m.usageCount);
  }

  /// Average daily usage per machine type based on the oldest machine
  /// creation date. Returns 0 when there is no data.
  static double averageDailyUsage(List<MachineModel> machines, String type) {
    final list = machines.where((m) => m.type == type).toList();
    if (list.isEmpty) return 0;

    final totalUsage = list.fold<int>(0, (sum, m) => sum + m.usageCount);

    final now = DateTime.now();
    DateTime? oldestCreated;
    for (final m in list) {
      if (oldestCreated == null || m.createdAt.isBefore(oldestCreated)) {
        oldestCreated = m.createdAt;
      }
    }
    if (oldestCreated == null) return 0;

    final days = now.difference(oldestCreated).inHours / 24.0;
    if (days <= 0) return 0;
    return totalUsage / days;
  }

  /// Machines of a type whose usageCount >= maintenanceThreshold.
  static List<MachineModel> machinesNeedingMaintenance(
    List<MachineModel> machines,
    String type,
  ) {
    return machines
        .where(
          (m) =>
              m.type == type &&
              m.usageCount >= AppConstants.maintenanceThreshold,
        )
        .toList();
  }

  /// FIFO ordering for waiting loads: oldest `createdAt` first (queue
  /// position #1 = oldest). This is what the scheduler uses to decide which
  /// waiting load gets the next available machine.
  static List<OrderLoadModel> sortWaitingLoadsFifo(
    List<OrderLoadModel> loads,
  ) {
    final copy = List<OrderLoadModel>.from(loads);
    copy.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return copy;
  }

  /// Whether a load already has a machine assigned for the given stage type
  /// (`wash` or `dry`). Enforces the state invariant: a load must NEVER be
  /// "Waiting for Machine/Dryer" while a washer/dryer is already assigned to
  /// it (that would mean a machine is reserved with the load still waiting).
  static bool hasAssignedMachine(OrderLoadModel load, String type) {
    final id = type == AppConstants.machineWasher
        ? load.assignedWasherId
        : load.assignedDryerId;
    return id != null && id.isNotEmpty;
  }
}
